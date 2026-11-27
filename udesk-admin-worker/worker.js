// UDesk super-admin OTP worker (Cloudflare Workers).
//
// Holds the admin ed25519 private key and releases it to the admin tool ONLY after the
// caller proves two factors:
//   1. a valid Firebase ID token for the admin's UID (Google login), and
//   2. a one-time code emailed to the admin.
// The admin binary bakes no private key; without passing both factors it cannot sign.
//
// Secrets / vars (set with `wrangler secret put` or in the dashboard):
//   FIREBASE_PROJECT   = "utc-next"                 (var)
//   ADMIN_UID          = the admin's Firebase UID    (var)
//   ADMIN_EMAIL        = where the OTP is sent        (secret)
//   SENDER_EMAIL       = a verified Resend sender     (var, e.g. "udesk@your-domain")
//   RESEND_API_KEY     = Resend API key               (secret)
//   ADMIN_PRIVATE_KEY  = sodium 64-byte secret, base64 (secret)  <- the key being protected
// KV binding: OTP_KV  (stores the pending OTP, short-lived)
//
// Endpoints (POST, JSON):
//   /request-otp  { idToken }          -> emails an OTP, {ok:true}
//   /verify-otp   { idToken, otp }     -> { key: "<private key b64>" } on success

const JWKS_URL =
  "https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com";
const OTP_TTL_SECONDS = 300;
const MAX_ATTEMPTS = 5;

export default {
  async fetch(request, env) {
    if (request.method !== "POST") return json({ error: "POST only" }, 405);
    const url = new URL(request.url);
    let body;
    try {
      body = await request.json();
    } catch {
      return json({ error: "bad json" }, 400);
    }
    const uid = await verifyAdminToken(body.idToken, env);
    if (!uid) return json({ error: "unauthorized" }, 401);

    if (url.pathname === "/request-otp") return requestOtp(env);
    if (url.pathname === "/verify-otp") return verifyOtp(body.otp, env);
    return json({ error: "not found" }, 404);
  },
};

async function requestOtp(env) {
  const otp = String(Math.floor(100000 + Math.random() * 900000));
  const record = { hash: await sha256(otp), exp: Date.now() + OTP_TTL_SECONDS * 1000, tries: 0 };
  await env.OTP_KV.put("otp:" + env.ADMIN_UID, JSON.stringify(record), {
    expirationTtl: OTP_TTL_SECONDS,
  });
  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${env.RESEND_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from: env.SENDER_EMAIL,
      to: env.ADMIN_EMAIL,
      subject: `UDesk Admin code: ${otp}`,
      text: `Your UDesk admin verification code is ${otp}. It expires in 5 minutes. If you did not request it, ignore this email.`,
    }),
  });
  if (!res.ok) return json({ error: "email failed" }, 502);
  return json({ ok: true });
}

async function verifyOtp(otp, env) {
  const raw = await env.OTP_KV.get("otp:" + env.ADMIN_UID);
  if (!raw) return json({ error: "no otp" }, 400);
  const record = JSON.parse(raw);
  if (Date.now() > record.exp) {
    await env.OTP_KV.delete("otp:" + env.ADMIN_UID);
    return json({ error: "expired" }, 400);
  }
  if (record.tries >= MAX_ATTEMPTS) {
    await env.OTP_KV.delete("otp:" + env.ADMIN_UID);
    return json({ error: "too many attempts" }, 429);
  }
  if (!otp || (await sha256(String(otp))) !== record.hash) {
    record.tries += 1;
    await env.OTP_KV.put("otp:" + env.ADMIN_UID, JSON.stringify(record), {
      expirationTtl: OTP_TTL_SECONDS,
    });
    return json({ error: "wrong code" }, 401);
  }
  await env.OTP_KV.delete("otp:" + env.ADMIN_UID);
  // Both factors passed: release the private key for this session only.
  return json({ key: env.ADMIN_PRIVATE_KEY });
}

// Verify a Firebase ID token (RS256) and that its subject is the admin UID.
async function verifyAdminToken(idToken, env) {
  try {
    if (!idToken || typeof idToken !== "string") return null;
    const [h, p, s] = idToken.split(".");
    if (!h || !p || !s) return null;
    const header = JSON.parse(b64urlToString(h));
    const payload = JSON.parse(b64urlToString(p));
    const now = Math.floor(Date.now() / 1000);
    const project = env.FIREBASE_PROJECT;
    if (
      payload.aud !== project ||
      payload.iss !== `https://securetoken.google.com/${project}` ||
      payload.exp <= now ||
      payload.sub !== env.ADMIN_UID
    ) {
      return null;
    }
    const jwks = await (await fetch(JWKS_URL)).json();
    const jwk = jwks.keys.find((k) => k.kid === header.kid);
    if (!jwk) return null;
    const key = await crypto.subtle.importKey(
      "jwk",
      jwk,
      { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
      false,
      ["verify"]
    );
    const ok = await crypto.subtle.verify(
      "RSASSA-PKCS1-v1_5",
      key,
      b64urlToBytes(s),
      new TextEncoder().encode(`${h}.${p}`)
    );
    return ok ? payload.sub : null;
  } catch {
    return null;
  }
}

async function sha256(str) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(str));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}
function b64urlToBytes(s) {
  s = s.replace(/-/g, "+").replace(/_/g, "/");
  const bin = atob(s + "===".slice((s.length + 3) % 4));
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}
function b64urlToString(s) {
  return new TextDecoder().decode(b64urlToBytes(s));
}
function json(obj, status = 200) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

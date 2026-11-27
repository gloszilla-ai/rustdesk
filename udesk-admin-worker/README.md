# UDesk super-admin OTP worker — ขั้นตอน setup

Worker นี้เก็บกุญแจส่วนตัวของแอดมิน และปล่อยให้ตัวแอดมินก็ต่อเมื่อผ่าน **Google login (บัญชีแอดมิน) + OTP ทางอีเมล**
ตัวแอดมินจึงไม่ต้องฝังกุญแจในไบนารีอีกต่อไป ไม่ผ่าน 2FA = ไม่มีกุญแจ = เซ็นไม่ได้

## สิ่งที่ต้องมี

1. บัญชี Cloudflare (มี Workers — free plan พอ)
2. บัญชี Resend (resend.com, free tier) + ยืนยันโดเมน/อีเมลผู้ส่ง 1 อัน + สร้าง API key
3. UID แอดมินใน Firebase (ของบัญชี Google ที่ใช้เป็นแอดมิน — ผมช่วยหาให้ได้)
4. กุญแจส่วนตัวแอดมิน: ค่า `sodium_secret_b64` ในไฟล์ `D:\udesk-tools\udesk-admin-key.json`

## ขั้นตอน (ใช้ wrangler)

```powershell
npm i -g wrangler
wrangler login
```

สร้าง KV แล้วเอา id ไปใส่ใน `wrangler.toml`:

```powershell
wrangler kv namespace create OTP_KV
```

แก้ `wrangler.toml`: ใส่ `ADMIN_UID`, `SENDER_EMAIL` (อีเมลผู้ส่งที่ยืนยันกับ Resend), และ `id` ของ KV

ตั้งค่า secret (ไม่ขึ้น git):

```powershell
wrangler secret put ADMIN_EMAIL
wrangler secret put RESEND_API_KEY
wrangler secret put ADMIN_PRIVATE_KEY
```

`ADMIN_PRIVATE_KEY` ใส่ค่า `sodium_secret_b64` จากไฟล์กุญแจ (ความลับสูงสุด)

deploy:

```powershell
wrangler deploy
```

ได้ URL เช่น `https://udesk-admin-otp.<subdomain>.workers.dev` — เอา URL นี้ไปใส่ในแอป (จะบอกตอนทำฝั่งแอป)

## endpoint

- `POST /request-otp` body `{idToken}` → ส่ง OTP เข้าอีเมลแอดมิน
- `POST /verify-otp` body `{idToken, otp}` → คืน `{key}` (กุญแจส่วนตัว) เมื่อถูก

## ความปลอดภัย

- `idToken` คือ Firebase ID token ของบัญชีแอดมิน Worker ตรวจลายเซ็น JWT กับกุญแจสาธารณะของ Google
  และตรวจว่า UID ตรงกับ `ADMIN_UID` เท่านั้น
- OTP เก็บเป็น hash อายุ 5 นาที ลองผิดได้ไม่เกิน 5 ครั้ง
- กุญแจส่วนตัวไม่เคยอยู่ในไบนารี ส่งผ่าน HTTPS หลังผ่าน 2FA เท่านั้น ตัวแอดมินถือไว้ใน RAM ต่อรอบ
- **ห้าม commit** ค่า secret ใด ๆ repo เป็น public

# UDesk — ระบบแอดมินสูงสุด (super-admin) — สถานะปัจจุบัน + เอกสารส่งต่องาน

> เอกสารนี้สรุป **สิ่งที่ทำจริงแล้ว** (ไม่ใช่ร่าง) ให้โมเดล/คนทำงานต่อเข้าใจทั้งระบบและทำส่วนที่เหลือได้
> คู่กับ `super-admin-design.md` (แผนตั้งต้น) และ `CHAT-LOG.md` (ประสานงานกับแชท Mac)
> อัปเดตล่าสุด: 2026-11-28 — UDesk v1.0.5 (branch `udesk`)

---

## 1. ภาพรวม: ระบบทำอะไร

เจ้าของงาน (แอดมินสูงสุดคนเดียว) รีโมทเข้าเครื่องสำนักงาน (20-30 เครื่อง) ได้แบบ **เงียบ ไร้ร่องรอย**
— ไม่ต้องรหัสผ่าน, เครื่องปลายทางไม่เด้งกล่อง, ไม่มีร่องรอยใน taskbar/tray — โดยยังปลอดภัย
(ต้องผ่าน 2FA + ถือ private key) และเครื่องสำนักงานใช้ **ตัวโปรแกรมที่ต่างจากตัวสาธารณะแค่ env ตอน build**

**สถานะ: ใช้งานได้จริง ทดสอบผ่านครบ** (รีโมท, ถ่ายโอนไฟล์ ส่ง+ดึง, ไม่มีกล่อง/taskbar/tray-count)
ค้าง: ดูกล้องเปิดกล้องได้แต่ภาพไม่ขึ้น (บั๊กฟีเจอร์กล้อง) + ระบบหลังบ้าน/แดชบอร์ด (ยังไม่เริ่ม)

---

## 2. สถาปัตยกรรมความปลอดภัย (สำคัญสุด — อ่านก่อนแตะโค้ด auth)

### คู่กุญแจ ed25519
- สร้างครั้งเดียว เก็บที่ **`D:\udesk-tools\udesk-admin-key.json`** (เครื่องแอดมินเท่านั้น, **ไม่ขึ้น git**)
  - `public_b64` = public key (เปิดเผยได้)
  - `sodium_secret_b64` = private key 64 ไบต์ (ความลับสูงสุด — ห้ามหลุด ห้าม commit)
- **public key ฝังในเครื่องเป้าหมายแบบ gate ด้วย env** `UDESK_ADMIN_PUB_KEY` ตอน `cargo build`
  - โค้ด: `libs/base/src/lib.rs` → `pub const UDESK_ADMIN_PUB_KEY: Option<&str> = option_env!("UDESK_ADMIN_PUB_KEY");`
  - **build ที่ไม่ตั้ง env นี้ = ไม่มี public key = ไม่รับแอดมินเลย** (ตัวสาธารณะปลอดภัย)
  - **build ที่ตั้ง env = เครื่องนั้นยอมให้แอดมินเข้าเงียบ** (ตัวออฟฟิศเท่านั้น)
- **private key ไม่เคยอยู่ในไบนารีเลย** — ตัวแอดมิน (ตัวคุม) ดึง private key จาก Cloudflare Worker หลังผ่าน 2FA
  แล้วถือใน RAM อย่างเดียว (`UDESK_ADMIN_RUNTIME_KEY` ใน `src/client.rs`) ปิดโปรแกรม = หาย

### 2FA (ต้องผ่านก่อนตัวแอดมินได้ private key)
- ชั้น 1: **Google login** (บัญชีแอดมิน UID ที่กำหนด) — ผ่าน `UdeskAuth` (`flutter/lib/udesk/udesk_auth.dart`)
- ชั้น 2: **OTP ทางอีเมล** — ผ่าน **Cloudflare Worker** (`udesk-admin-worker/`) + Cloudflare Email Sending
  - Worker ตรวจ Firebase ID token (JWKS RS256) → `/request-otp` ส่ง OTP → `/verify-otp` ตรวจแล้วคืน `ADMIN_PRIVATE_KEY`
  - Dart: `flutter/lib/udesk/udesk_admin_2fa.dart` (`UdeskAdmin2FA.ensureUnlocked()`)
  - Worker URL อยู่ใน **`D:\udesk-tools\udesk-worker-url.txt`** (deploy แล้ว ทดสอบผ่าน)
  - Secret ใน Cloudflare (ตั้งเอง ไม่อยู่ repo): `ADMIN_PRIVATE_KEY` (= sodium_secret_b64), `ADMIN_UID`

### การเชื่อมต่อแบบแอดมิน (silent)
1. ตัวแอดมินปลดล็อก 2FA → ได้ private key ใน RAM
2. เชื่อมต่อเครื่องเป้าหมาย: เป้าหมายส่ง `Hash.admin_challenge` (nonce 32 ไบต์)
3. ตัวแอดมินเซ็น `challenge || target_id` ด้วย private key → ใส่ใน `LoginRequest.admin_signature`
   **และ clear `lr.password`** (โหมดแอดมินไม่ใช้รหัสผ่านเลย — กัน race direct/relay เข้าทางรหัสผ่าน)
4. เป้าหมายตรวจลายเซ็นกับ public key ที่ฝัง → ผ่าน = รับเงียบ (ไม่ถามรหัส ไม่เด้งกล่อง)

**proto ที่เพิ่ม** (`libs/base/protos/message.proto`): `Hash.admin_challenge`, `LoginRequest.admin_signature`

---

## 3. ไฟล์โค้ดหลัก (จุดที่แก้)

| ไฟล์ | ทำอะไร |
|---|---|
| `libs/base/src/lib.rs` | `UDESK_ADMIN_PUB_KEY` (option_env, gate public key) |
| `libs/base/protos/message.proto` | `Hash.admin_challenge`, `LoginRequest.admin_signature` |
| `src/server/connection.rs` | ฝั่งเป้าหมาย: สร้าง challenge, `verify_admin_signature()`, admin branch (รับเงียบ), `UDESK_ADMIN_CONNS` (กัน tray นับ session แอดมิน) |
| `src/client.rs` | ฝั่งตัวคุม: `udesk_admin_sign()`, clear password โหมดแอดมิน, `UDESK_ADMIN_RUNTIME_KEY`, `set_udesk_admin_key()` |
| `src/ipc.rs` | tray session count ใช้ `udesk_non_admin_alive_count()` |
| `src/flutter_ffi.rs` | `main_set_common("udesk-admin-key", ...)` → ตั้ง runtime key |
| `src/ui_cm_interface.rs` | ส่ง `is_admin` ไป CM (Flutter) |
| `flutter/lib/main.dart` | CM เริ่มซ่อน + `setSkipTaskbar` ตอนซ่อน (ไม่มีหน้าต่างค้าง taskbar) |
| `flutter/lib/models/server_model.dart` | `_udeskAdminOnly()` ซ่อนกล่องเมื่อ client ที่ authorized เป็นแอดมินล้วน |
| `flutter/lib/udesk/udesk_admin_2fa.dart` | flow 2FA ฝั่งตัวแอดมิน |
| `flutter/lib/udesk/udesk_auth.dart` | Google login + `idToken()` |
| `flutter/lib/udesk/udesk_update.dart` | `_kVersionUrl` = `String.fromEnvironment('UDESK_UPDATE_URL', default public)` → ตัวออฟฟิศเช็กช่องแยก |
| `flutter/lib/common.dart` | gate: ตัวแอดมินต้องปลด 2FA ก่อน connect + กันเข้า ID ตัวเอง |
| `flutter/lib/consts.dart` | `kUDeskVersion`, `kUdeskAdminTool`, `kUdeskOfficeInstallUrl` |
| `src/auth_2fa.rs` | `ISSUER = "UDesk"` |
| `udesk-admin-worker/` | Cloudflare Worker (worker.js, wrangler.toml, README.md) |

---

## 4. ธงตอน build (dart-define / env)

| ธง | ที่ | ตัวไหนตั้ง |
|---|---|---|
| `UDESK_ADMIN_PUB_KEY` | env ตอน `cargo build` | **ตัวออฟฟิศ** (เป้าหมาย) เท่านั้น |
| `UDESK_ADMIN_TOOL=1` | `--dart-define` | **ตัวแอดมิน** (ตัวคุม) เท่านั้น |
| `UDESK_OTP_WORKER_URL` | `--dart-define` | ตัวแอดมิน (URL worker) |
| `UDESK_UPDATE_URL` | `--dart-define` | ตัวออฟฟิศ → `.../office/version.json` (กันอัปเดตข้ามไปตัวไม่มี pubkey) |

**3 ตัวโปรแกรม:**
- **ตัวสาธารณะ** (homepage): ไม่ตั้ง env ใด = ไม่มี pubkey, ไม่ใช่ตัวคุม
- **ตัวออฟฟิศ** (เป้าหมาย 20-30 เครื่อง): `UDESK_ADMIN_PUB_KEY` + `UDESK_UPDATE_URL=.../office/version.json`
- **ตัวแอดมิน** (ตัวคุมของเจ้าของงาน): `UDESK_ADMIN_TOOL=1` + `UDESK_OTP_WORKER_URL` (+ pubkey เพื่อความสม่ำเสมอ)

---

## 5. เว็บ + ระบบปล่อยรุ่น (desk.unext.studio, Firebase project `utc-next`, site `unext-desk`)

- โฟลเดอร์เว็บ: `udesk-web/` (`index.html`, `versions.html`, `mac.html`, `version.json`, `download/`, firebase config)
- deploy: `cd udesk-web && firebase deploy` (แทนที่ทั้งไซต์ — `download/` ต้องมีไฟล์ติดตั้งครบก่อน deploy)
- **สองช่องปล่อยรุ่น (ปลอดภัย):**
  - **สาธารณะ**: `version.json` + ปุ่มใน `index.html`/`versions.html` → `download/UDesk-1.0.5-install.exe` (**ไม่มี pubkey**)
  - **ออฟฟิศ**: `office/version.json` + `download/office/UDesk-office-install.exe` (**มี pubkey**) — **ไม่ลิงก์หน้าเว็บ**
    เจ้าของงานเปิด URL ตรง `https://desk.unext.studio/download/office/UDesk-office-install.exe` ลงทีละเครื่อง
    (ลิงก์นี้โชว์ที่หน้า "เกี่ยวกับ" ของตัวแอดมินด้วย มีปุ่มคัดลอก — `kUdeskOfficeInstallUrl`)
- **เหตุผลแยกช่อง**: ถ้าฝัง pubkey ลงตัวสาธารณะ = ใครโหลดก็ถูกแอดมินเข้าได้ = backdoor + เจ้าของงานผิดกฎหมาย
  ช่องออฟฟิศแยก + `UDESK_UPDATE_URL` แยก → เครื่องออฟฟิศอัปเดตเฉพาะตัว pubkey ไม่มีวันเผลอ downgrade

### ประสานกับแชท Mac (ผ่าน `CHAT-LOG.md` ใน GitHub)
- ไฟล์ที่สองฝั่งแก้ร่วม: `version.json`, `index.html`, `versions.html`, `consts.dart` → **แจ้งใน CHAT-LOG ก่อนแก้**
- ก่อน `firebase deploy` ฝั่ง Windows ต้องมี `.dmg` ของ Mac ครบใน `download/` (ไม่งั้นลิงก์ Mac หาย)

---

## 6. เครื่องมือ build (local เท่านั้น — ไม่ขึ้น git)

ทุกอย่างอยู่ **`D:\udesk-tools\`**:
- `env.bat` (vcvars64, Flutter 3.24.5, PUB_CACHE), `udesk-secrets.json` (dart-define-from-file: Google OAuth ฯลฯ)
- `udesk-admin-key.json` (คู่กุญแจ), `udesk-worker-url.txt` (Worker URL)
- `build-release.bat` (build ตัวออฟฟิศ+ตัวสาธารณะ), `build-superadmin.bat` (ตัวแอดมิน), `build-office.bat`
- `dist/` (ตัวติดตั้งที่ build ออกมา)
- ลำดับ build: `cargo build --locked --features hwcodec,flutter --lib --release` (~4.5 นาที, ตั้ง env pubkey ถ้าต้องการ)
  → `flutter build windows --release --dart-define-from-file=...` → pack ด้วย `libs/portable/generate.py`

---

## 7. งานที่เหลือ

### ก. บั๊กดูกล้อง (view camera)
- อาการ: กด "ดูกล้อง" → ไฟเว็บแคมเครื่องเป้าหมายติด (เปิดกล้องได้) แต่**ภาพไม่ขึ้นฝั่งตัวคุม**
- การเชื่อม view-camera ใช้ลายเซ็นแอดมินเหมือนกัน (เงียบ) — ปัญหาอยู่ที่สตรีม/เรนเดอร์กล้อง ไม่ใช่ auth
- ต้องดีบั๊กแยก: เก็บ log ทั้งสองฝั่ง**ตอนกดดูกล้อง** หาว่าหลุดตรง encode/decode/render

### ข. ระบบหลังบ้าน / แดชบอร์ดแอดมิน (ยังไม่เริ่ม — งานของโมเดลถัดไป)
ตาม `super-admin-design.md` เป้าหมาย:
- **แผงแอดมินแสดงเครื่องทั้งหมด** ที่ติดตั้ง UDesk พร้อม **ภาพย่อหน้าจอล่าสุด** (ออนไลน์=ภาพ, ออฟไลน์=จอดำ)
  — ใช้ `UdeskThumb` (ภาพย่อที่มีอยู่แล้ว)
- ดึงรายชื่อเครื่องจาก **Firestore** (ระบบ log เดิม `udesk_log` มี device ID, เวลา, เวอร์ชัน — ดู `flutter/lib/udesk/udesk_log.dart`)
- gate แดชบอร์ด: เปิดได้เฉพาะบัญชี Google แอดมิน (UID ตรง) — ตรวจที่ UI + Firestore rules
- กดการ์ดเครื่อง → ปลด 2FA (ถ้ายังไม่ปลด) → เข้ารีโมทเงียบ
- **หมายเหตุ**: เจ้าของงานจะให้โมเดลอื่น (fable 5.2) ออกแบบ/ทำส่วนนี้ — Firebase project `utc-next`

### ค. cleanup
- โค้ดโหมดแอดมินแบบรหัสผ่านเดิม (`kUdeskAdmin`, `udesk_admin.dart`, `build-admin.bat`) เลิกใช้แล้ว (inert) — ลบได้

---

## 8. commit/branch
- branch `udesk` (repo public: `github.com/gloszilla-ai/rustdesk`)
- commit ล่าสุดของระบบเงียบ: `5837591` (silent connect leaves no trace)
- ห้าม commit: `D:\udesk-tools\*` (กุญแจ/secret), `.wrangler/` cache

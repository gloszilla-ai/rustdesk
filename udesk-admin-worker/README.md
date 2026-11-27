# UDesk super-admin OTP worker — setup

Worker เก็บกุญแจส่วนตัวของแอดมิน ปล่อยให้ตัวแอดมินก็ต่อเมื่อผ่าน **Google login (บัญชีแอดมิน) + OTP อีเมล**
ส่งอีเมลผ่าน **Cloudflare Email Sending** (ไม่ต้องใช้ผู้ให้บริการอื่น) ไม่ผ่าน 2FA = ไม่มีกุญแจ = เซ็นไม่ได้

## ต้องมี

1. บัญชี Cloudflare + โดเมนที่ onboard กับ Email Sending แล้ว (unext.studio เปิดอยู่แล้ว)
2. ยืนยันอีเมลแอดมินเป็น **destination address** (แผน Free ส่งได้เฉพาะปลายทางที่ยืนยัน):
   Cloudflare → Email Service → Email Routing → Destination Addresses → เพิ่ม `gloszilla@gmail.com` → คลิกลิงก์ยืนยันในเมล
3. กุญแจส่วนตัว: ค่า `sodium_secret_b64` ในไฟล์ `D:\udesk-tools\udesk-admin-key.json`

## deploy ด้วย wrangler

```powershell
cd D:\NKBKDESK\fork\rustdesk\udesk-admin-worker
npx wrangler login
npx wrangler kv namespace create OTP_KV
```

เอา id ของ KV ไปใส่ใน `wrangler.toml` (`PUT_KV_NAMESPACE_ID_HERE`), ตรวจ `ADMIN_UID` และ `SENDER_EMAIL` (ที่อยู่ผู้ส่งบนโดเมนที่ onboard)

ตั้ง secret:

```powershell
npx wrangler secret put ADMIN_EMAIL        # gloszilla@gmail.com (ที่ยืนยันแล้ว)
npx wrangler secret put ADMIN_PRIVATE_KEY  # ค่า sodium_secret_b64 (ความลับสูงสุด)
npx wrangler deploy
```

ได้ URL เช่น `https://udesk-admin-otp.<subdomain>.workers.dev`
เอา URL นี้ไปใส่ใน `D:\udesk-tools\udesk-worker-url.txt` แล้วรัน `D:\udesk-tools\build-superadmin.bat` เพื่อ build ตัวแอดมินที่รู้จัก Worker

## endpoint

- `POST /request-otp` {idToken} → ส่ง OTP เข้าอีเมลแอดมิน
- `POST /verify-otp` {idToken, otp} → คืน {key} เมื่อถูก

## ความปลอดภัย

- `idToken` = Firebase ID token ของบัญชีแอดมิน Worker ตรวจลายเซ็น JWT กับกุญแจสาธารณะของ Google และ UID = `ADMIN_UID` เท่านั้น
- OTP เก็บเป็น hash อายุ 5 นาที ลองผิดไม่เกิน 5 ครั้ง
- กุญแจส่วนตัวไม่เคยอยู่ในไบนารี ส่งผ่าน HTTPS หลัง 2FA เท่านั้น ถือใน RAM ต่อรอบ
- **ห้าม commit** ค่า secret repo เป็น public

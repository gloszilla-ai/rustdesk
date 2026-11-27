# UDesk server (hbbs + hbbr)

รันบน Synology NAS ด้วย Container Manager

| อะไร | ค่า |
|---|---|
| ที่อยู่ที่ฝังใน UDesk | `rs.unext.studio` (Cloudflare A record ชี้ไป public IP ของ NAS, DNS only) |
| NAS | ที่อยู่ LAN, public IP และหน้าจัดการ ไม่บันทึกใน repo สาธารณะ (อยู่ในไฟล์ส่วนตัวของผู้ดูแล) |
| Project | `udesk-server` ใน Container Manager, โฟลเดอร์ `/volume1/docker/udesk` |
| Compose | [nas/docker-compose.yml](nas/docker-compose.yml) — image `rustdesk/rustdesk-server:latest`, `network_mode: host`, `restart: unless-stopped` |
| Container | `udesk-hbbs`, `udesk-hbbr` |
| ข้อมูล + กุญแจ | `/volume1/docker/udesk/data` (`id_ed25519`, `id_ed25519.pub`, `db_v2.sqlite3`) |
| Public key | `6LqyVqgnEDth+L5vtpc6+BSrpKJVvM13Q1NJAfepUM0=` |

`id_ed25519` (ไม่มี .pub) คือกุญแจลับ ห้ามเผยแพร่ และต้องสำรองไว้ ถ้าหายต้อง build UDesk ใหม่ทุกเครื่อง

## พอร์ตที่ต้องเปิดจากอินเทอร์เน็ตมาที่ NAS

| พอร์ต | โปรโตคอล | ใช้ทำอะไร |
|---|---|---|
| 21115 | TCP | ทดสอบชนิด NAT |
| 21116 | TCP + UDP | ลงทะเบียน ID, hole punching |
| 21117 | TCP | relay |
| 21118, 21119 | TCP | WebSocket (ไม่จำเป็น เว้นแต่จะใช้ผ่าน Cloudflare Tunnel) |

Cloudflare ต้องตั้งเป็น **DNS only (เมฆสีเทา)** เพราะ proxy ของ Cloudflare ไม่รับ TCP/UDP ดิบ

## สถานะ (27 พ.ย. 2026)

- [x] hbbs/hbbr รันบน NAS พอร์ต 21115–21117 เข้าถึงได้จากใน LAN
- [x] UDesk ฝัง `desk.unext.studio` + public key ของ NAS แล้ว build ผ่าน (push ขึ้น fork แล้ว)
- [x] DNS: สร้าง A record `desk.unext.studio` ที่ Cloudflare แล้ว
- [x] ทดสอบผ่าน LAN: UDesk ลงทะเบียน ID กับ hbbs บน NAS ได้ (log `update_pk`) — key ถูกต้อง
- [x] Router forward พอร์ตแล้ว: `desk.unext.studio` พอร์ต 21115–21117 ตอบ และ UDesk ลงทะเบียนผ่านชื่อโดเมนได้ (ทดสอบจากใน LAN เท่านั้น ยังไม่ได้ทดสอบจากเครือข่ายภายนอกและยังไม่ได้ทดสอบรีโมทระหว่างสองเครื่อง)
- [ ] โฟลเดอร์ `/volume1/docker/udesk-server` บน NAS เป็นของเหลือจากการสร้างครั้งแรกที่ล้ม ลบได้

Server ชั่วคราวบน PC (`D:\udesk-server`) หยุดแล้ว เก็บไฟล์ไว้เผื่อใช้ทดสอบ

## เว็บไซต์ desk.unext.studio

- โฮสต์บน **Firebase Hosting** site `unext-desk` (project `utc-next`) ไม่ได้อยู่บน NAS
- DNS: `desk.unext.studio` CNAME → `unext-desk.web.app` (Cloudflare, DNS only)
- Deploy: `cd udesk-web` แล้ว `firebase deploy --only hosting:unext-desk`
- เซิร์ฟเวอร์รีโมทใช้ชื่อแยก `rs.unext.studio` เพราะ Firebase รับได้เฉพาะเว็บ ไม่รับพอร์ต 21115–21117

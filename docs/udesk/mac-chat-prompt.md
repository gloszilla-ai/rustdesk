# Prompt สำหรับเปิดแชทใหม่บนเครื่อง Mac

คัดลอกข้อความในกรอบด้านล่างไปวางเป็นข้อความแรกของแชทใหม่ (Claude Code บนเครื่อง Mac)

```text
ผมต้องการให้คุณ build และทำตัวติดตั้ง UDesk สำหรับ macOS บนเครื่องนี้

UDesk คือ fork ของ RustDesk ที่เปลี่ยนแบรนด์แล้ว ฝั่ง Windows ทำเสร็จและใช้งานได้ ฝั่ง macOS ยังไม่เคย build

เริ่มจาก:
1. clone repo: git clone --recurse-submodules -b udesk https://github.com/gloszilla-ai/rustdesk.git
2. อ่าน docs/UDESK-MAC.md ให้จบก่อนทำอะไร เอกสารนี้บอกเวอร์ชันเครื่องมือ ขั้นตอน สิ่งที่แก้ไปแล้ว งานเฉพาะ macOS และข้อควรระวัง
3. อ่าน docs/udesk/udesk-known-issues.md เพื่อรู้ว่าอะไรยังค้าง
4. ไฟล์ secret สำหรับปุ่ม Google login อยู่ที่ ~/udesk-secrets.json (ผมวางไว้ให้แล้ว) ใช้ตอน build ตามที่เอกสารบอก ห้าม commit ไฟล์นี้ และห้ามพิมพ์ค่าข้างในออกมาในแชท

เป้าหมายตามลำดับ:
1. ติดตั้งเครื่องมือและ build ให้ผ่านโดยยังไม่แก้โค้ด เปิดโปรแกรมแล้วส่งภาพหน้าจอจริงให้ผมดู ต้องเห็นชื่อ UDesk ภาษาไทย ฟอนต์ Anuphan หน้าหลักแถบน้ำเงิน และสถานะ "พร้อม"
2. ทำรายการ "งานเฉพาะ macOS ที่ต้องทำ" ในเอกสาร (ชื่อแอป bundle id ไอคอน ลิงก์ที่ยังชี้ไป rustdesk แถบขอสิทธิ์ Google login)
3. ทำตัวติดตั้ง .dmg ทั้ง Apple Silicon และ Intel ถ้าทำได้
4. ทำระบบอัปเดตฝั่ง mac: เพิ่ม key "macos" ใน udesk-web/version.json เปิดปุ่ม "ตรวจหาอัปเดต" ให้ mac และเพิ่มลิงก์ดาวน์โหลด mac ในเว็บ (udesk-web/index.html, versions.html)

กติกา:
- คุยกับผมเป็นภาษาไทย
- ลงมือทำเองจนจบแล้วส่งภาพหน้าจอจริง ไม่ต้องให้ขั้นตอนผมไปทำเอง ยกเว้นสิ่งที่ต้องใช้รหัสผ่านหรือบัญชี Apple ของผม
- ถามผมก่อนในเรื่อง: bundle id, Apple Developer ID / code signing, และการ deploy เว็บ
- commit ลง branch udesk เดียวกัน ก่อน push ให้ git pull --rebase ทุกครั้ง เพราะฝั่ง Windows ยัง commit อยู่
- แก้เท่าที่จำเป็น ตาม AGENTS.md ของ repo
- repo เป็น public ห้าม commit รหัสผ่าน secret IP ภายใน หรือชื่อเครื่องภายใน
- อย่าลบบรรทัด "Powered by RustDesk (AGPL-3.0)" และอย่าเอาขั้นตอนขออนุญาตของฝั่งถูกควบคุมออก
- ถ้าทำอะไรไม่ได้หรือยังไม่ได้ทดสอบ ให้บอกตรง ๆ
```

## สิ่งที่ต้องเตรียมบนเครื่อง Mac ก่อนเปิดแชท

1. **ไฟล์ secret:** คัดลอก `D:\udesk-tools\udesk-secrets.json` จากเครื่อง Windows ไปวางที่ `~/udesk-secrets.json` บน Mac
   ส่งทางช่องทางส่วนตัว (AirDrop, USB, ที่เก็บไฟล์ส่วนตัว) อย่าส่งผ่านแชทสาธารณะหรือ commit
2. **ไฟล์โลโก้ต้นฉบับ:** `D:\udesk-tools\brand\logo.png` (ตัว U น้ำเงิน-ส้ม) สำหรับทำไอคอนแอปของ mac
3. **Xcode** ติดตั้งจาก App Store และเปิดหนึ่งครั้งเพื่อยอมรับเงื่อนไข (แชทติดตั้งให้ไม่ได้เพราะต้องใช้บัญชี Apple)
4. **บัญชี GitHub** ที่ push เข้า `gloszilla-ai/rustdesk` ได้ ล็อกอินไว้ในเครื่อง (`gh auth login`)
5. ถ้าจะ deploy เว็บจาก Mac: `firebase login` ด้วยบัญชีที่เข้าถึง project `utc-next`

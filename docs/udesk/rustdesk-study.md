# ศึกษา RustDesk (open-source) เพื่อใช้กับ NkbkDesk

อ่านจาก README / Cargo.toml / docs ของ repo ทั้งสองเมื่อ 27 พ.ย. 2026

| | [rustdesk/rustdesk](https://github.com/rustdesk/rustdesk) | [rustdesk/rustdesk-server](https://github.com/rustdesk/rustdesk-server) |
|---|---|---|
| คืออะไร | ตัวโปรแกรม client (ทั้งฝั่งควบคุมและฝั่งถูกควบคุม) | ID/Rendezvous server + Relay server |
| License | AGPL-3.0 | AGPL-3.0 |
| ภาษา | Rust (core) + Flutter/Dart (UI) — UI เก่า Sciter เลิกใช้แล้ว | Rust |
| เวอร์ชันใน Cargo.toml | 1.5.3 | — |
| ดาวบน GitHub | ~132k | ~10.8k |

## 1. rustdesk-server

`cargo build --release` ได้ 3 ไฟล์

| ไฟล์ | หน้าที่ | เทียบกับ NkbkDesk ตอนนี้ |
|---|---|---|
| `hbbs` | ID / Rendezvous server: ลงทะเบียน ID, จับคู่, ช่วยเจาะ NAT | `server/index.js` |
| `hbbr` | Relay server: ส่งต่อข้อมูลเมื่อ P2P ไม่ได้ | coturn (TURN) |
| `rustdesk-utils` | เครื่องมือ CLI | — |

**พอร์ต**

| พอร์ต | โปรแกรม | ใช้ทำอะไร |
|---|---|---|
| 21115 TCP | hbbs | ทดสอบชนิด NAT |
| 21116 TCP + UDP | hbbs | ลงทะเบียน ID, rendezvous, hole punching |
| 21117 TCP | hbbr | relay |
| 21118 TCP | hbbs | WebSocket (เฉพาะ web client) |
| 21119 TCP | hbbr | WebSocket relay (เฉพาะ web client) |

> พอร์ต 21116 ชนกับ signaling server ของ NkbkDesk ที่ทำไว้ ถ้าจะรันทั้งคู่บนเครื่องเดียวต้องเปลี่ยนพอร์ตฝั่งใดฝั่งหนึ่ง

**รันด้วย Docker** — image `rustdesk/rustdesk-server-s6` รันทั้ง hbbs และ hbbr ในตัวเดียว

```yaml
services:
  rustdesk-server:
    image: rustdesk/rustdesk-server-s6:latest
    environment:
      - RELAY=desk.example.com:21117
      - ENCRYPTED_ONLY=1
    ports:
      - "21115:21115"
      - "21116:21116"
      - "21116:21116/udp"
      - "21117:21117"
    volumes:
      - ./data:/data
    restart: unless-stopped
```

- `RELAY` = ที่อยู่ relay ที่ hbbs จะบอก client
- `ENCRYPTED_ONLY=1` = รับเฉพาะ client ที่ใส่ key ถูกต้อง
- ตอนเริ่มครั้งแรก server สร้างคู่กุญแจ `id_ed25519` / `id_ed25519.pub` ไว้ใน `/data` — ค่าใน `.pub` คือ **Key** ที่ต้องใส่ใน client
- hbbr ต้องได้ key เดียวกับ hbbs จึงจะตรวจ key ตอน relay

## 2. rustdesk (client)

**โครงสร้างโค้ด**

| ที่อยู่ | หน้าที่ |
|---|---|
| `libs/hbb_common` | config, ตัวห่อ TCP/UDP, utility ที่ใช้ร่วมกับ server |
| `libs/scrap` | จับภาพหน้าจอ + video codec |
| `libs/enigo` | ควบคุมเมาส์/คีย์บอร์ดแยกตาม OS |
| `libs/clipboard` | copy/paste ไฟล์ (Windows, Linux, macOS) |
| `src/server` | บริการฝั่งถูกควบคุม: เสียง, clipboard, input, วิดีโอ, การเชื่อมต่อ |
| `src/client.rs` | เริ่มการเชื่อมต่อไปยังอีกเครื่อง |
| `src/rendezvous_mediator.rs` | คุยกับ rustdesk-server รอการต่อตรง (TCP hole punch) หรือผ่าน relay |
| `src/platform` | โค้ดเฉพาะแต่ละ OS |
| `flutter` | UI ของ desktop และ mobile |

**สิ่งที่ต้องมีเพื่อ build บน Windows**
1. Rust + C++ build tools (Visual Studio Build Tools)
2. vcpkg (ตั้ง `VCPKG_ROOT`) แล้วติดตั้ง
   `vcpkg install libvpx:x64-windows-static libyuv:x64-windows-static opus:x64-windows-static aom:x64-windows-static`
3. Flutter SDK สำหรับ UI — README ไม่ได้ให้คำสั่ง ให้ดูขั้นตอนจริงใน `.github/workflows/flutter-build.yml`
4. `cargo run` (ตามด้วยขั้นตอน Flutter ตาม workflow)

เครื่องนี้ยังไม่มี Rust, vcpkg และ Flutter — ต้องติดตั้งทั้งหมดก่อน (หลาย GB และ build ครั้งแรกนาน)

## 3. เงื่อนไข AGPL-3.0 ที่ต้องรู้ก่อน fork

- โปรแกรมที่ดัดแปลงจาก RustDesk ต้องเป็น AGPL-3.0 ด้วย และต้องให้ source code กับผู้ที่ได้รับโปรแกรมไป
- ถ้าดัดแปลง server แล้วเปิดให้คนอื่นใช้ผ่านเครือข่าย ต้องให้ source ของส่วนที่ดัดแปลงด้วย
- ต้องคงข้อความลิขสิทธิ์และ license เดิมไว้
- เรื่องการใช้ชื่อ/โลโก้ "RustDesk" ผมยังไม่ได้ตรวจนโยบายเครื่องหมายการค้า — ถ้า rebrand ควรเปลี่ยนชื่อและโลโก้ทั้งหมดเป็น NkbkDesk
- ถ้าจะขายหรือใช้เชิงพาณิชย์ ควรให้นักกฎหมายตรวจอีกครั้ง

## 4. ทางเลือกสำหรับ NkbkDesk

| ทางเลือก | ได้อะไร | ต้องแลกกับ |
|---|---|---|
| **A. ใช้ RustDesk ตามเดิม + ตั้ง server เอง** | ใช้งานได้ทันที ครบทุกฟีเจอร์ ข้อมูลผ่าน server ของตัวเอง | ชื่อโปรแกรมยังเป็น RustDesk |
| **B. Fork RustDesk แล้วเปลี่ยนแบรนด์เป็น NkbkDesk** | โปรแกรมชื่อ NkbkDesk ที่ฟีเจอร์ครบและผ่านการใช้งานจริงมาแล้ว | ต้องติดตั้ง toolchain หนัก, ต้องเปิด source ตาม AGPL, ต้องตาม merge อัปเดตจากต้นทางเอง |
| **C. ทำ NkbkDesk (Electron) ที่มีอยู่ต่อ** | โค้ดเป็นของเราเอง ไม่ติด AGPL เข้าใจง่าย | ฟีเจอร์และประสิทธิภาพตามหลัง RustDesk มาก |

**คำแนะนำ:** เริ่มจาก A (ตั้ง `rustdesk-server` เองแล้วชี้ client มาที่ server นั้น) เพื่อให้ใช้งานได้จริงก่อน แล้วค่อยทำ B ถ้าต้องการแบรนด์ NkbkDesk
โค้ด Electron ที่ทำไว้ (Phase 1–3) เก็บไว้เป็นตัวศึกษา/ต้นแบบได้

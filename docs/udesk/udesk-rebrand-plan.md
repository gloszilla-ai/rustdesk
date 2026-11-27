# แผน Fork RustDesk → UDesk

ซอร์สที่ clone ไว้ (27 พ.ย. 2026, shallow, อยู่ใน `fork/` ซึ่งถูก ignore จาก repo นี้)

| โฟลเดอร์ | commit | หมายเหตุ |
|---|---|---|
| `fork/rustdesk` | `45e34a6` (เวอร์ชัน 1.5.3) | มี submodule `libs/hbb_common` |
| `fork/rustdesk-server` | `680b603` | มี submodule `libs/hbb_common` (คนละ commit) |

## 1. ต้อง fork 3 repo
ชื่อแอปและ server เริ่มต้นอยู่ใน `hbb_common` ซึ่งเป็น submodule แยก repo จึงต้อง fork ทั้ง

1. `rustdesk/rustdesk` → client
2. `rustdesk/hbb_common` → ค่าคงที่ชื่อแอป/server (แล้วแก้ `.gitmodules` ของ client ให้ชี้มาที่ fork นี้)
3. `rustdesk/rustdesk-server` → ถ้าใช้ image `rustdesk/rustdesk-server-s6` ตามเดิมโดยไม่แก้โค้ด **ไม่ต้อง fork**

## 2. จุดที่ต้องแก้ใน client

| เรื่อง | ไฟล์ | ค่าปัจจุบัน → ค่าใหม่ |
|---|---|---|
| ชื่อแอป | `libs/hbb_common/src/config.rs:71` | `APP_NAME = "RustDesk"` → `"UDesk"` (โฟลเดอร์ config/log ใช้ชื่อนี้) |
| องค์กร | `libs/hbb_common/src/config.rs:57` | `ORG = "com.carriez"` → ของเราเอง |
| **ID server เริ่มต้น** | `libs/hbb_common/src/config.rs:116` | `RENDEZVOUS_SERVERS = ["rs-ny.rustdesk.com"]` → server ของเรา |
| **Public key ของ server** | `libs/hbb_common/src/config.rs:117` | `RS_PUB_KEY` → ค่าใน `id_ed25519.pub` ของ server เรา |
| ลิงก์เอกสาร | `libs/hbb_common/src/config.rs:99-100` | `rustdesk.com/docs` → ของเรา หรือคงไว้ |
| ตรวจอัปเดต | `src/common.rs:1186` | `api.rustdesk.com/version/latest` → **ต้องปิดหรือชี้มาที่ของเรา** ไม่งั้นจะชวนผู้ใช้อัปเดตเป็น RustDesk ตัวจริง |
| API/admin เริ่มต้น | `src/common.rs:1320` | `admin.rustdesk.com` → ปิด/ของเรา |
| ข้อมูลไฟล์ .exe | `Cargo.toml:261-283` | `ProductName`, `FileDescription`, `OriginalFilename`, bundle `name`/`identifier` |
| ข้อมูลไฟล์ (Flutter) | `flutter/windows/runner/Runner.rc:93-98` | เหมือนกัน |
| ชื่อ binary | `flutter/windows/CMakeLists.txt:7`, `build.py:26,945,956` | `rustdesk` → `udesk` |
| ชื่อหน้าต่างสำรอง | `flutter/windows/runner/main.cpp:87` | `L"RustDesk"` → `L"UDesk"` |
| ไอคอน/โลโก้ | `res/icon.ico`, `res/icon.png`, `res/*.png`, `res/logo*.svg`, `res/tray-icon.ico`, `flutter/assets/` | ต้องมีโลโก้ UDesk |
| ตัวติดตั้ง MSI | `res/msi/` | ชื่อสินค้า, ผู้ผลิต, UpgradeCode ใหม่ |
| ข้อความใน UI | `src/lang/*.rs`, `flutter/lib/` | คำว่า "RustDesk" ปรากฏ ~2,700 ครั้งใน 175 ไฟล์ — ส่วนใหญ่ดึงจาก `APP_NAME` แต่ต้องไล่ตรวจที่เขียนตรง ๆ |

**สิ่งที่จะไม่แก้:** ข้อความลิขสิทธิ์เดิม, ไฟล์ `LICENCE` (AGPL-3.0), หน้าต่างขออนุญาต/แจ้งเตือนฝั่งถูกควบคุม
**สิ่งที่จะเพิ่ม:** ในหน้า About ระบุว่า "UDesk พัฒนาต่อจาก RustDesk (AGPL-3.0)" พร้อมลิงก์ source ของ fork

> `custom.txt` (ระบบ custom client ในตัว) ใช้ไม่ได้กับงานนี้ — ไฟล์ต้องเซ็นด้วยกุญแจของ RustDesk Server Pro จึงต้องแก้ที่ซอร์สโดยตรง

## 3. เครื่องมือ build (อ้างอิง `.github/workflows/flutter-build.yml`)

| เครื่องมือ | เวอร์ชันที่ CI ใช้ | เครื่องนี้ |
|---|---|---|
| Rust | 1.75 (ตรึงไว้เพราะ Sciter; build Flutter ใช้ใหม่กว่าได้ ต้องลองจริง) | มี 1.99.1 |
| Visual Studio Build Tools (C++) | 2022 | มีแล้ว |
| Flutter | 3.24.5 (+ engine ที่ RustDesk แก้เอง และ patch ใน workflow) | **ยังไม่มี** |
| LLVM/Clang | 15.0.6 | **ยังไม่มี** |
| vcpkg | commit `9e593bb1` (2026.07.29), triplet `x64-windows-static` | **ยังไม่มี** |
| ไลบรารีผ่าน vcpkg | aom, libjpeg-turbo, opus, libvpx, libyuv, mfx-dispatch, ffmpeg ฯลฯ ตาม `vcpkg.json` | **ยังไม่มี** (compile เองทั้งหมด ใช้เวลานาน) |
| Python 3 | สำหรับ `build.py` | มี 3.12 |
| flutter_rust_bridge codegen | ตาม `bridge.yml` | **ยังไม่มี** |

คำสั่ง build หลัก: `python build.py --portable --flutter --skip-portable-pack --hwcodec`
พื้นที่ดิสก์: D: ว่าง 223 GB เพียงพอ (คาดว่าใช้ราว 15–25 GB รวม cache)

## 4. สิ่งที่ต้องได้จากคุณ

1. **Server** — โดเมนหรือ IP ของเครื่องที่จะรัน `hbbs`/`hbbr` และค่า public key หลังรันครั้งแรก (ถ้ายังไม่มี ใส่ค่าชั่วคราวแล้วเปลี่ยนทีหลังได้ แต่แอปจะยังเชื่อมต่อใครไม่ได้)
2. **โลโก้ UDesk** — ไฟล์ SVG/PNG (ถ้าไม่มี ผมทำโลโก้ตัวอักษรชั่วคราวให้ได้)
3. **บัญชี GitHub ที่จะวาง fork** — ตอนนี้ `gh` login เป็น `gloszilla-ai`; fork จะเป็น public (AGPL บังคับให้เปิด source อยู่แล้ว)
4. **เรื่องชื่อ** — "Udesk" เป็นชื่อแบรนด์ซอฟต์แวร์ customer service ที่มีอยู่แล้ว ถ้าจะเผยแพร่เชิงพาณิชย์ควรตรวจเครื่องหมายการค้าก่อน

## 5. ลำดับงาน

1. Fork `hbb_common` + `rustdesk` ไปที่ GitHub แล้วชี้ submodule
2. ติดตั้ง Flutter 3.24.5, LLVM 15, vcpkg + ไลบรารี
3. **Build ซอร์สเดิมให้ผ่านก่อน** (ยังไม่แก้อะไร) เพื่อยืนยันว่า toolchain ใช้ได้
4. แก้ชื่อ/ไอคอน/server ตามตารางข้อ 2 → build → ทดสอบ 2 เครื่อง
5. ตั้ง `rustdesk-server` (Docker) แล้วใส่ที่อยู่ + key จริง
6. ทำตัวติดตั้ง (MSI/EXE) ชื่อ UDesk

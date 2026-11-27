# วิธี build UDesk (fork ของ RustDesk) บนเครื่องนี้

| อะไร | อยู่ที่ไหน |
|---|---|
| ซอร์ส client | `D:\NKBKDESK\fork\rustdesk` — branch `udesk` (origin = `gloszilla-ai/rustdesk`, upstream = `rustdesk/rustdesk`) |
| submodule | `libs\hbb_common` — branch `udesk` (origin = `gloszilla-ai/hbb_common`) |
| ซอร์ส server | `D:\NKBKDESK\fork\rustdesk-server` (ยังไม่แก้) |
| เครื่องมือ | `D:\udesk-tools` — Flutter 3.24.5 (ใส่ patch dropdown ตาม CI แล้ว), vcpkg `9e593bb1` + ไลบรารี `x64-windows-static`, libclang 15.0.6 |
| ตั้งค่า environment | `D:\udesk-tools\env.bat` (เรียก `vcvars64` + ตั้ง `VCPKG_ROOT`, `LIBCLANG_PATH`, PATH ของ Flutter) |
| ไอคอน | `D:\udesk-tools\brand\` |
| Rust | โฟลเดอร์ซอร์สตรึงไว้ที่ 1.75 ด้วย `rustup override` (เท่ากับที่ CI ใช้) |

## ขั้นตอน (รันใน cmd)

```bat
call D:\udesk-tools\env.bat
cd /d D:\NKBKDESK\fork\rustdesk

rem 1) สร้างไฟล์ bridge (ทำใหม่เมื่อ src\flutter_ffi.rs เปลี่ยน)
rem    ต้องตั้ง CPATH ให้เจอ stdbool.h ไม่เช่นนั้น bool ใน Dart จะถูกสร้างผิดชนิดและ UI คอมไพล์ไม่ผ่าน
set CPATH=D:\udesk-tools\llvm\include
flutter_rust_bridge_codegen --rust-input ./src/flutter_ffi.rs --dart-output ./flutter/lib/generated_bridge.dart --c-output ./flutter/macos/Runner/bridge_generated.h --llvm-path D:\udesk-tools\llvm

rem 2) ส่วน Rust (~5 นาที)
cargo build --locked --features hwcodec,flutter --lib --release

rem 3) ส่วน UI — ต้องเปิด Developer Mode ของ Windows ก่อน
cd flutter
flutter build windows --release --dart-define-from-file=D:\udesk-tools\udesk-secrets.json
```

ผลลัพธ์อยู่ที่ `flutter\build\windows\x64\runner\Release\` (`dylib_virtual_display.dll` ของจอเสมือนยังไม่ได้ build — เป็นส่วนเสริม)
(หรือใช้ `python build.py --portable --flutter --skip-portable-pack --hwcodec` ซึ่งทำข้อ 2–3 ให้)

## สถานะ (27 พ.ย. 2026)

- [x] Build ส่วน Rust ของซอร์สเดิมผ่าน
- [x] แก้แบรนด์เป็น UDesk แล้ว build ส่วน Rust ผ่าน (`librustdesk.dll` 39 MB)
- [x] Build ส่วน UI (Flutter) ผ่าน — ได้ `flutter\build\windows\x64\runner\Release\rustdesk.exe` เปิดแล้วชื่อหน้าต่างเป็น UDesk. ครั้งแรกต้องรัน `D:\udesk-tools\build-ui.bat` แบบ Administrator เพื่อสร้าง symlink ของ plugin (Developer Mode ปิดอยู่) หลังจากนั้น build แบบปกติได้. pub cache อยู่ที่ `D:\udesk-tools\pub-cache` (`PUB_CACHE` ใน `env.bat`)
- [x] ใส่ไอคอนจริง — ต้นฉบับ `D:\udesk-tools\brand\logo.png` แปลงด้วย `D:\udesk-tools\brand\make-icons.py`
- [x] Push branch `udesk` ขึ้น fork ทั้งสอง repo แล้ว และ `.gitmodules` ชี้ไป `gloszilla-ai/hbb_common`
- [ ] ใส่ที่อยู่ server จริง + public key ใน `libs/hbb_common/src/config.rs` (ตอนนี้เป็น `udesk-server.invalid`)
- [ ] ตัวติดตั้ง, เปลี่ยนชื่อไฟล์ `rustdesk.exe`/`librustdesk.dll`, driver เสริม (จอเสมือน, เครื่องพิมพ์), custom Flutter engine ของ RustDesk

## สิ่งที่แก้ไปแล้ว

- `libs/hbb_common/src/config.rs`: `APP_NAME = "UDesk"`, `ORG = "com.udesk"`, server เริ่มต้นเป็นค่าชั่วคราว, ไม่มี key เริ่มต้น
- `Cargo.toml`, `flutter/windows/runner/Runner.rc`, `main.cpp`: ชื่อสินค้าในข้อมูลไฟล์และชื่อหน้าต่างสำรอง
- ไอคอน: `res/icon.ico`, `res/tray-icon.ico`, `res/*.png`, `flutter/windows/runner/resources/app_icon.ico`, `flutter/assets/icon.svg`
- หน้า About: เพิ่มบรรทัด "UDesk is based on RustDesk (AGPL-3.0). Source code" ลิงก์ไป fork — ข้อความลิขสิทธิ์เดิมคงไว้

เมื่อชื่อแอปไม่ใช่ "RustDesk" โค้ดต้นทางถือว่าเป็น custom client และปิดการตรวจอัปเดตจาก RustDesk ให้เอง (`is_custom_client()` ใน `src/common.rs`)

## Google sign-in (Firebase project utc-next)

- โค้ดอยู่ที่ `flutter/lib/udesk/udesk_auth.dart` — OAuth client ชนิด Desktop ชื่อ "UDesk Desktop" ใน Google Cloud ของ `utc-next`
- client secret **ไม่อยู่ใน git** (GitHub push protection กันไว้) เก็บที่ `D:\udesk-tools\udesk-secrets.json` แล้วส่งเข้าตอน build ด้วย `--dart-define-from-file` ถ้า build โดยไม่ใส่ ปุ่ม login จะขึ้นว่าล้มเหลว
- เครื่อง Mac ต้องมีไฟล์นี้เช่นกัน ส่งให้กันทางช่องทางส่วนตัว ห้าม commit

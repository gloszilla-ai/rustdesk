# UDesk บน macOS — เอกสารส่งต่อ

เอกสารนี้เขียนให้คน (หรือแชท Claude) ที่จะ build และทำตัวติดตั้ง UDesk บน macOS อ่านแล้วเริ่มงานได้เลย
สถานะ ณ 27 พ.ย. 2026: ฝั่ง Windows build และใช้งานได้แล้ว **ฝั่ง macOS ยังไม่เคย build**

## UDesk คืออะไร

UDesk คือ fork ของ [RustDesk](https://github.com/rustdesk/rustdesk) (AGPL-3.0) v1.5.3 ที่เปลี่ยนแบรนด์และหน้าตา
และชี้ไปที่เซิร์ฟเวอร์ของเราเอง เจ้าของงานสื่อสารเป็นภาษาไทย

| อะไร | ค่า |
|---|---|
| Repo client | `https://github.com/gloszilla-ai/rustdesk` branch **`udesk`** |
| Submodule | `libs/hbb_common` → `https://github.com/gloszilla-ai/hbb_common` branch **`udesk`** |
| Upstream | `https://github.com/rustdesk/rustdesk` (commit ฐาน `45e34a6`) |
| เซิร์ฟเวอร์ ID/relay | `desk.unext.studio` (hbbs/hbbr บน Synology NAS, พอร์ต TCP 21115–21117, UDP 21116) |
| Public key ของเซิร์ฟเวอร์ | ฝังอยู่ใน `libs/hbb_common/src/config.rs` (`RS_PUB_KEY`) |
| ชื่อแอป / org | `UDesk` / `com.udesk` (`APP_NAME`, `ORG` ใน `config.rs`) |
| เวอร์ชันที่ผู้ใช้เห็น | `1.0.0` (`kUDeskVersion` ใน `flutter/lib/consts.dart`) |

เลขเวอร์ชันของ crate ยังเป็น `1.5.3` โดยตั้งใจ เพราะเครื่องสองฝั่งใช้เลขนี้เทียบกันว่าจะเปิดฟีเจอร์ไหน **อย่าเปลี่ยน**

## เริ่มต้น

```sh
git clone --recurse-submodules -b udesk https://github.com/gloszilla-ai/rustdesk.git
cd rustdesk
git -C libs/hbb_common checkout udesk
```

ขั้นตอน build ของ macOS ให้ยึดตาม workflow ของ upstream ใน `.github/workflows/flutter-build.yml` (job ของ macOS)
ซึ่งระบุเวอร์ชันที่ใช้จริง สิ่งที่ฝั่ง Windows ใช้และผ่านแล้ว:

- Rust: Windows ใช้ **1.75** แต่ **macOS ต้องใช้ 1.81** (`MAC_RUST_VERSION` ใน workflow เพราะ crate `cidre`)
- Flutter **3.24.5** (upstream มี patch เล็ก ๆ ให้ Flutter ดูใน workflow)
- vcpkg commit `9e593bb18ea69cc5095e012465dcd675a822ed0d` (`VCPKG_COMMIT_ID`), ติดตั้งแบบ manifest (`vcpkg.json` ที่ราก repo)
- `flutter_rust_bridge_codegen` **1.80.1**, `cargo-expand` 1.0.95, libclang 15

### ไฟล์ bridge ต้องสร้างเอง

`src/bridge_generated.rs`, `src/bridge_generated.io.rs`, `flutter/lib/generated_bridge.dart` ถูก gitignore ต้องสร้างด้วย:

```sh
flutter_rust_bridge_codegen --rust-input ./src/flutter_ffi.rs \
  --dart-output ./flutter/lib/generated_bridge.dart \
  --c-output ./flutter/macos/Runner/bridge_generated.h
```

บทเรียนจาก Windows: ถ้า codegen หา `stdbool.h` ไม่เจอ ชนิด `bool` ใน Dart จะถูกสร้างผิดเป็น
`NativeFunction<Int Function(Pointer<Int>)>` แล้ว UI คอมไพล์ไม่ผ่านเป็นพันจุด ให้ตรวจว่า `generated_bridge.dart`
มีคำว่า `ffi.Bool` ก่อนไปต่อ (บน macOS ที่มี Xcode ปกติจะไม่เจอปัญหานี้)

### ค่า secret ตอน build (สำคัญ)

ปุ่ม "เข้าสู่ระบบด้วย Google" ต้องใช้ client secret ของ OAuth client ซึ่ง **ไม่อยู่ใน git**
(GitHub push protection กันไว้) เจ้าของงานจะส่งไฟล์ `udesk-secrets.json` ให้ทางช่องทางส่วนตัว รูปแบบ:

```json
{"UDESK_GOOGLE_CLIENT_SECRET":"..."}
```

ทุกคำสั่ง build ของ Flutter ต้องเติม `--dart-define-from-file=/path/to/udesk-secrets.json`
ถ้า `build.py` เรียก `flutter build` ให้เอง ต้องแก้ให้ส่ง flag นี้ต่อ หรือเรียก `flutter build macos --release --dart-define-from-file=...` เอง
ถ้าไม่ใส่ โปรแกรมยัง build ได้ แต่ปุ่ม login จะขึ้นว่าล้มเหลว **ห้าม commit ไฟล์นี้**

## สิ่งที่แก้จาก upstream แล้ว (ใช้ร่วมกันทุกระบบ)

- **แบรนด์:** ชื่อ, ไอคอน (`res/`, `flutter/assets/icon.svg`), ตัดลิงก์ไป rustdesk.com ออกจากหน้าหลัก/About/Install
  หน้า About เหลือบรรทัด `Powered by RustDesk (AGPL-3.0)` ลิงก์ไปซอร์สของเรา **อย่าลบบรรทัดนี้**
- **ภาษา:** ค่าเริ่มต้นเป็นไทย (`src/lang.rs`), ฟอนต์ Anuphan ฝังใน `flutter/assets/fonts/`
- **หน้าหลัก (ดีไซน์ "C"):** แถบหัวน้ำเงินไล่สีแสดง ID/รหัสผ่าน, แถบแจ้งเตือนสีส้ม, ช่องเชื่อมต่อเต็มความกว้าง,
  แท็บมีข้อความ, แถบชื่อหน้าต่างน้ำเงินเข้ม — `flutter/lib/desktop/pages/desktop_home_page.dart`,
  `connection_page.dart`, `common/widgets/peer_tab_page.dart`, `desktop/widgets/tabbar_widget.dart`
- **หน้าตั้งค่า:** แท็บแนวนอนด้านบน, การ์ดเรียง 1–3 คอลัมน์ตามความกว้าง — `desktop_setting_page.dart`
- **Login:** Google sign-in ผ่าน Firebase (project `utc-next`) — `flutter/lib/udesk/udesk_auth.dart`
- **บันทึกการใช้งาน:** ส่ง event เข้า Firestore database `udesk` — `flutter/lib/udesk/udesk_log.dart`
  (เก็บเฉพาะ ID เครื่อง, ID ปลายทาง, เวลา, ประเภท ห้ามเพิ่มรหัสผ่าน/ภาพหน้าจอ/การกดแป้น/เนื้อหาไฟล์)

สีหลัก: น้ำเงินเข้ม `#071A4D`, น้ำเงิน `#0A3FBF` / `#0A74E8`, ส้ม `#F58A00`
ภาพร่างดีไซน์ทุกหน้า: https://claude.ai/artifact/8z2k4dX4uptq7qUpqTZHEp (ต้องให้เจ้าของงานแชร์ก่อนจึงเปิดได้)

## งานเฉพาะ macOS ที่ต้องทำ

1. **Build ให้ผ่านก่อน** โดยยังไม่แก้อะไร แล้วเปิดดูว่าชื่อ UDesk, ภาษาไทย, ฟอนต์, หน้าหลักแบบ C ขึ้นถูก
   และสถานะด้านล่างเป็น "พร้อม" (เชื่อม `desk.unext.studio` ได้)
2. **ตรวจจุดที่ยังเป็น RustDesk ในส่วน macOS** ซึ่งฝั่ง Windows ไม่ได้แตะ:
   - `flutter/macos/Runner/Configs/AppInfo.xcconfig`: ตอนนี้ยังเป็น `PRODUCT_NAME = RustDesk`, `PRODUCT_BUNDLE_IDENTIFIER = com.carriez.flutterHbb` และ `PRODUCT_COPYRIGHT` ของ upstream (เสนอ bundle id `com.udesk.UDesk` — ถามเจ้าของงานก่อน เพราะผูกกับ Apple Developer ID), และ `Info.plist`
   - ไอคอนแอปใน `flutter/macos/Runner/Assets.xcassets/` และ `res/mac-icon.png`, tray icon `res/mac-tray-*.png`
     (ไฟล์ต้นฉบับโลโก้ขอจากเจ้าของงาน: ตัว U น้ำเงิน-ส้ม พื้นโปร่งใส)
   - ลิงก์คู่มือสิทธิ์ของ mac: key `doc_mac_permission` ใน `src/lang/en.rs` ยังชี้ไป rustdesk.com
   - ชื่อ service/daemon และ plist ใน `src/platform/` กับ `res/` (privileged helper) ถ้ามีคำว่า rustdesk ที่ผู้ใช้เห็น
3. **แถบแจ้งเตือนสิทธิ์:** บน macOS หน้าหลักจะขึ้นแถบส้มขอสิทธิ์ Screen Recording / Accessibility / Input Monitoring
   (โค้ดอยู่ใน `buildHelpCards` → `_buildUdeskBanner`) ตรวจว่าปุ่ม "Configure" ทำงานและข้อความไม่ล้น
4. **แถบชื่อหน้าต่าง:** บน macOS โค้ดซ่อนโลโก้/ชื่อในแถบ (`Offstage(offstage: kUseCompatibleUiMode || isMacOS ...)`)
   และใช้ปุ่มไฟจราจรของระบบ ตรวจว่าแถบน้ำเงินเข้มเข้ากับปุ่มของระบบ
5. **Google login:** flow ใช้เบราว์เซอร์ + loopback `http://127.0.0.1:<port>` ควรทำงานบน macOS ได้เลย
   **จุดเสี่ยง:** `flutter/macos/Runner/Release.entitlements` เปิด app sandbox และมีแค่ `com.apple.security.network.client` การฟังพอร์ต loopback อาจถูกบล็อก ถ้า login ค้างที่ "กำลังรอการยืนยันในเบราว์เซอร์" ให้เพิ่ม `com.apple.security.network.server`
6. **ตัวติดตั้ง:** ทำ `.dmg` (upstream ใช้ `create-dmg` ใน workflow) ชื่อไฟล์ `UDesk-1.0.0-<arch>.dmg`
   ทั้ง Apple Silicon และ Intel ถ้าทำได้
7. **Code signing / notarization:** ต้องใช้ Apple Developer ID ของเจ้าของงาน ถ้ายังไม่มีให้แจ้งว่า
   ผู้ใช้จะเจอคำเตือน Gatekeeper และต้องคลิกขวา → Open

## ข้อควรระวัง

- เก็บ diff ให้เล็ก: `AGENTS.md` ของ repo ขอให้แก้เท่าที่จำเป็น ไม่จัดรูปแบบโค้ดเดิม ไม่ refactor
- อย่าชี้เซิร์ฟเวอร์เริ่มต้นกลับไปที่เซิร์ฟเวอร์สาธารณะของ RustDesk
- อย่าเอา consent ของฝั่งถูกควบคุมออก (รหัสผ่าน/กดยอมรับ และแถบแจ้งว่ากำลังถูกควบคุม)
- งานของ macOS ให้ commit ลง branch `udesk` เดียวกัน ก่อน push ให้ `git pull --rebase` เพราะฝั่ง Windows ยัง commit อยู่
- เจ้าของงานชอบให้ลงมือทำเองจนจบแล้วส่งภาพหน้าจอจริงให้ดู มากกว่าให้ขั้นตอนไปทำเอง

## ติดต่อกลับฝั่ง Windows

ถ้าต้องแก้โค้ดส่วนกลาง (ไม่ใช่เฉพาะ mac) ให้เขียนสั้น ๆ ไว้ใน commit message ว่าแก้อะไรเพราะอะไร
ฝั่ง Windows จะ pull และ build ตรวจอีกรอบ

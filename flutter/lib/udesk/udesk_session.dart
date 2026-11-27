import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter_hbb/models/platform_model.dart';

// UDesk: tells whether this window runs in a Windows session that is not the one on the
// physical screen. That is the case inside a Remote Desktop (RDP) session, and it stays
// so after RDP disconnects until someone signs in at the computer. The UDesk service then
// serves the sign-in screen, this window cannot talk to it, and any one-time password
// shown here is stale.
class UdeskSession {
  static final DynamicLibrary? _kernel32 =
      Platform.isWindows ? DynamicLibrary.open('kernel32.dll') : null;

  static bool get detached {
    final lib = _kernel32;
    if (lib == null) return false;
    try {
      final consoleId = lib.lookupFunction<Uint32 Function(), int Function()>(
          'WTSGetActiveConsoleSessionId')();
      final pid = lib.lookupFunction<Uint32 Function(), int Function()>(
          'GetCurrentProcessId')();
      final out = calloc<Uint32>();
      try {
        final ok = lib.lookupFunction<Int32 Function(Uint32, Pointer<Uint32>),
                int Function(int, Pointer<Uint32>)>('ProcessIdToSessionId')(
            pid, out);
        return ok != 0 && consoleId != 0xFFFFFFFF && out.value != consoleId;
      } finally {
        calloc.free(out);
      }
    } catch (_) {
      return false;
    }
  }

  static String get message {
    final lang = bind.mainGetLocalOption(key: 'lang');
    return lang.isEmpty || lang == 'th'
        ? 'ใช้ผ่าน Remote Desktop อยู่ รหัสครั้งเดียวใช้ไม่ได้จนกว่าจะล็อกอินที่หน้าเครื่อง (หรือใช้รหัสผ่านถาวร)'
        : 'This computer is in a Remote Desktop session, so the one-time password does not work now. Sign in at the computer, or use a permanent password.';
  }
}

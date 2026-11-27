import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/models/model.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:path_provider/path_provider.dart';

// UDesk: peer cards show the desktop of the device as it looked in the last session.
// A few seconds into a remote session one screenshot is requested through the existing
// screenshot feature, scaled down and stored on this computer only. Never upload these.
const _kThumbWidth = 480;
const kUdeskThumbOption = 'udesk-thumbs';

class UdeskThumb {
  static String? _dir;
  static final _scheduled = <String>{};
  static final _pending = <String>{};
  static final _cache = <String, MapEntry<DateTime, ImageProvider>>{};

  static bool get enabled =>
      bind.mainGetLocalOption(key: kUdeskThumbOption) != 'N';

  static Future<String> dir() async {
    if (_dir != null) return _dir!;
    final base = Platform.isWindows
        ? '${Platform.environment['APPDATA']}\\UDesk'
        : (await getApplicationSupportDirectory()).path;
    final d = Directory('$base${Platform.pathSeparator}thumbs');
    await d.create(recursive: true);
    return _dir = d.path;
  }

  static String _path(String dir, String id) =>
      '$dir${Platform.pathSeparator}${id.replaceAll(RegExp(r'[^0-9A-Za-z_.@-]'), '_')}.png';

  /// Call once from the main window so cards can look thumbnails up synchronously.
  static void init() {
    dir().catchError((e) {
      debugPrint('UDesk thumb: $e');
      return '';
    });
  }

  static ImageProvider? imageFor(String id) {
    final d = _dir;
    if (d == null || !enabled) return null;
    try {
      final file = File(_path(d, id));
      if (!file.existsSync()) return null;
      final modified = file.lastModifiedSync();
      final cached = _cache[id];
      if (cached != null && cached.key == modified) return cached.value;
      final image = MemoryImage(file.readAsBytesSync());
      _cache[id] = MapEntry(modified, image);
      return image;
    } catch (_) {
      return null;
    }
  }

  static Future<void> remove(String id) async {
    try {
      _cache.remove(id);
      final file = File(_path(await dir(), id));
      if (await file.exists()) await file.delete();
    } catch (e) {
      debugPrint('UDesk thumb: remove failed: $e');
    }
  }

  static Future<void> removeAll() async {
    try {
      _cache.clear();
      final d = Directory(await dir());
      await for (final f in d.list()) {
        if (f is File) await f.delete();
      }
    } catch (e) {
      debugPrint('UDesk thumb: removeAll failed: $e');
    }
  }

  /// Called when a remote session shows its first image; asks for one screenshot.
  static void schedule(FFI ffi) {
    if (!isDesktop || !enabled) return;
    final sid = ffi.sessionId.toString();
    if (!_scheduled.add(sid)) return;
    Timer(const Duration(seconds: 4), () {
      try {
        final display = ffi.ffiModel.pi.currentDisplay;
        if (display == kAllDisplayValue) return;
        if (ffi.ffiModel.timerScreenshot != null) return;
        final supported = bind.sessionGetCommonSync(
            sessionId: ffi.sessionId,
            key: 'is_screenshot_supported',
            param: '');
        if (supported != 'true') return;
        _pending.add(sid);
        bind.sessionTakeScreenshot(sessionId: ffi.sessionId, display: display);
        Timer(const Duration(seconds: 30), () => _pending.remove(sid));
      } catch (e) {
        debugPrint('UDesk thumb: request failed: $e');
      }
    });
  }

  /// Returns true when the screenshot event answers a thumbnail request, so the
  /// normal "save or copy" dialog must not be shown.
  static bool handle(
      Map<String, dynamic> evt, SessionID sessionId, String peerId) {
    if (!_pending.remove(sessionId.toString())) return false;
    if ('${evt['msg'] ?? ''}'.isEmpty) {
      _save(sessionId, peerId);
    }
    return true;
  }

  static Future<void> _save(SessionID sessionId, String peerId) async {
    try {
      final target = _path(await dir(), peerId);
      final full = '$target.full';
      final res = await bind.sessionHandleScreenshot(
          sessionId: sessionId, action: '0:$full');
      if (res.isNotEmpty) return;
      final fullFile = File(full);
      final codec = await ui.instantiateImageCodec(
          await fullFile.readAsBytes(),
          targetWidth: _kThumbWidth);
      final frame = await codec.getNextFrame();
      final data =
          await frame.image.toByteData(format: ui.ImageByteFormat.png);
      frame.image.dispose();
      await fullFile.delete();
      if (data != null) {
        await File(target).writeAsBytes(data.buffer.asUint8List(), flush: true);
      }
    } catch (e) {
      debugPrint('UDesk thumb: save failed: $e');
    }
  }
}

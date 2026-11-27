import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;

// UDesk update check. The website publishes version.json:
//   {"version": "1.0.1", "windows": {"url": "...", "sha256": "...", "size": 123},
//    "macos": {"arm64": {"url": "...", "sha256": "...", "size": 123}, "x86_64": {...}}}
// The installer is only run when it comes from our own download folder and its SHA-256
// matches version.json. Running it shows the normal install page, which installs over
// the current version. On macOS the verified .dmg is opened in Finder and the user drags
// the app to Applications.
const _kVersionUrl = 'https://desk.unext.studio/version.json';
const _kDownloadPrefix = 'https://desk.unext.studio/download/';

class UdeskUpdate {
  /// Newer version available, empty when up to date or unknown.
  static final latest = ''.obs;

  /// -1 when idle, 0..1 while downloading.
  static final progress = (-1.0).obs;
  static final error = ''.obs;

  static String _url = '';
  static String _sha256 = '';

  static bool get _thai {
    final lang = bind.mainGetLocalOption(key: 'lang');
    return lang.isEmpty || lang == 'th';
  }

  static String get message => error.value.isNotEmpty
      ? error.value
      : _thai
          ? 'มี UDesk เวอร์ชันใหม่ ${latest.value} (เครื่องนี้ใช้ $kUDeskVersion)'
          : 'UDesk ${latest.value} is available (this device has $kUDeskVersion)';

  static String get buttonText {
    final p = progress.value;
    if (p >= 0) {
      final pct = (p * 100).floor();
      return _thai ? 'กำลังดาวน์โหลด $pct%' : 'Downloading $pct%';
    }
    return _thai ? 'อัปเดต' : 'Update';
  }

  static int compare(String a, String b) {
    List<int> parts(String v) =>
        v.split('.').map((e) => int.tryParse(e.trim()) ?? 0).toList();
    final x = parts(a), y = parts(b);
    for (var i = 0; i < 3; i++) {
      final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
      if (d != 0) return d;
    }
    return 0;
  }

  /// Result of the last check: '', 'checking', 'latest', 'available' or 'error'.
  static final status = ''.obs;

  static String get statusText {
    switch (status.value) {
      case 'checking':
        return _thai ? 'กำลังตรวจสอบ…' : 'Checking…';
      case 'latest':
        return _thai ? 'เป็นเวอร์ชันล่าสุดแล้ว' : 'You have the latest version';
      case 'available':
        return _thai
            ? 'มีเวอร์ชันใหม่ ${latest.value}'
            : 'Version ${latest.value} is available';
      case 'error':
        return _thai
            ? 'ตรวจสอบไม่สำเร็จ ลองใหม่อีกครั้ง'
            : 'Could not check. Please try again.';
    }
    return '';
  }

  static String get checkText => _thai ? 'ตรวจหาอัปเดต' : 'Check for updates';

  /// Fire and forget: a failed check must never disturb the app.
  static Future<void> check() async {
    if (!(Platform.isWindows || Platform.isMacOS) ||
        status.value == 'checking') {
      return;
    }
    status.value = 'checking';
    await _check();
    if (status.value == 'checking') status.value = 'error';
  }

  static Future<void> _check() async {
    try {
      final resp = await http
          .get(Uri.parse(_kVersionUrl))
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return;
      final json = jsonDecode(utf8.decode(resp.bodyBytes));
      final entry = Platform.isMacOS
          ? (json['macos'] ??
              {})[Abi.current() == Abi.macosArm64 ? 'arm64' : 'x86_64']
          : json['windows'];
      // UDesk: prefer a per-platform version so Windows and macOS can ship separately;
      // fall back to the shared top-level version when an entry has none.
      final version =
          '${(entry is Map ? entry['version'] : null) ?? json['version'] ?? ''}';
      if (Platform.isMacOS && version.isNotEmpty && entry == null) {
        status.value = 'latest';
        return;
      }
      final url = '${entry?['url'] ?? ''}';
      final sha = '${entry?['sha256'] ?? ''}'.toLowerCase();
      if (version.isEmpty ||
          !url.startsWith(_kDownloadPrefix) ||
          !url.endsWith(Platform.isMacOS ? '.dmg' : 'install.exe') ||
          sha.length != 64) {
        return;
      }
      if (compare(version, kUDeskVersion) > 0) {
        _url = url;
        _sha256 = sha;
        latest.value = version;
        status.value = 'available';
      } else {
        status.value = 'latest';
      }
    } catch (e) {
      debugPrint('UDesk update: check failed: $e');
    }
  }

  static Future<void> install() async {
    if (progress.value >= 0 || _url.isEmpty) return;
    error.value = '';
    progress.value = 0;
    final client = http.Client();
    try {
      final sep = Platform.pathSeparator;
      final dir = Directory('${Directory.systemTemp.path}${sep}udesk-update');
      await dir.create(recursive: true);
      final file = File(
          '${dir.path}${sep}UDesk-${latest.value}${Platform.isMacOS ? '.dmg' : '-install.exe'}');
      final resp = await client.send(http.Request('GET', Uri.parse(_url)));
      if (resp.statusCode != 200) {
        throw 'HTTP ${resp.statusCode}';
      }
      final total = resp.contentLength ?? 0;
      var done = 0;
      final sink = file.openWrite();
      await for (final chunk in resp.stream) {
        sink.add(chunk);
        done += chunk.length;
        if (total > 0) progress.value = done / total;
      }
      await sink.close();
      final digest = await sha256.bind(file.openRead()).first;
      if (digest.toString() != _sha256) {
        await file.delete();
        throw 'checksum mismatch';
      }
      if (Platform.isMacOS) {
        final opened = await Process.run('open', [file.path]);
        if (opened.exitCode != 0) throw 'open failed: ${opened.stderr}';
        error.value = _thai
            ? 'เปิดตัวติดตั้งแล้ว ออกจาก UDesk แล้วลาก UDesk ไปที่ Applications'
            : 'Installer opened. Quit UDesk, then drag UDesk to Applications.';
        return;
      }
      await Process.start(file.path, [], mode: ProcessStartMode.detached);
    } catch (e) {
      debugPrint('UDesk update: install failed: $e');
      error.value = _thai
          ? 'ดาวน์โหลดอัปเดตไม่สำเร็จ ลองใหม่อีกครั้ง'
          : 'Update download failed. Please try again.';
    } finally {
      client.close();
      progress.value = -1;
    }
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/udesk/udesk_auth.dart';
import 'package:http/http.dart' as http;

// UDesk usage log: appends one document per event to the Firestore database "udesk" of
// project utc-next. The database rules only allow creating documents with the fields
// written here; clients cannot read, change or delete anything.
//
// Only connection metadata is recorded. Never add passwords, screen contents, keystrokes,
// clipboard or file contents here.
const _kEventsUrl =
    'https://firestore.googleapis.com/v1/projects/utc-next/databases/udesk/documents/events';
const _kFirebaseApiKey = 'AIzaSyCxmHe1Y18OWlT6Uj3NaMXCUhywWJFp-2w';

class UdeskLog {
  static final _incomingSince = <int, DateTime>{};

  static Map<String, dynamic> _s(String v) => {'stringValue': v};
  static Map<String, dynamic> _i(int v) => {'integerValue': '$v'};

  /// Fire and forget: logging must never block or break the app.
  static Future<void> event(String type,
      {String? peer, String? kind, int? dur, int? files, int? bytes}) async {
    try {
      final device = (await bind.mainGetMyId()).replaceAll(' ', '');
      UdeskAuth.load();
      final fields = <String, dynamic>{
        'type': _s(type),
        'device': _s(device),
        'ver': _s(kUDeskVersion),
        'os': _s(Platform.operatingSystem),
        'ts': {
          'timestampValue': DateTime.now().toUtc().toIso8601String(),
        },
        if (peer != null && peer.isNotEmpty) 'peer': _s(peer),
        if (kind != null) 'kind': _s(kind),
        if (dur != null) 'dur': _i(dur),
        if (files != null) 'files': _i(files),
        if (bytes != null) 'bytes': _i(bytes),
        if (UdeskAuth.uid.value.isNotEmpty) 'uid': _s(UdeskAuth.uid.value),
        if (UdeskAuth.email.value.isNotEmpty)
          'email': _s(UdeskAuth.email.value),
      };
      final resp = await http
          .post(Uri.parse('$_kEventsUrl?key=$_kFirebaseApiKey'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'fields': fields}))
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) {
        debugPrint('UDesk log: $type -> ${resp.statusCode}');
      }
    } catch (e) {
      debugPrint('UDesk log: $type failed: $e');
    }
  }

  static void incomingStarted(int connId, String peer, bool isFileTransfer) {
    if (_incomingSince.containsKey(connId)) return;
    _incomingSince[connId] = DateTime.now();
    event('connect_in', peer: peer, kind: isFileTransfer ? 'file' : 'screen');
  }

  static void incomingEnded(int connId, String peer) {
    final since = _incomingSince.remove(connId);
    if (since == null) return;
    event('disconnect_in',
        peer: peer, dur: DateTime.now().difference(since).inSeconds);
  }
}

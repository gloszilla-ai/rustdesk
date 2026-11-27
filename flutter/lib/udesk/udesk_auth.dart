import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

// Google sign-in for UDesk, backed by Firebase Authentication (project utc-next).
//
// The secret of a "Desktop app" OAuth client is required by Google's token endpoint but is
// not confidential once shipped. It still stays out of this public repository: pass it at
// build time with --dart-define=UDESK_GOOGLE_CLIENT_SECRET=... (see docs/udesk-build.md).
const _kGoogleClientId =
    '316123564455-qp6qehc2r17ke1s5npsa56h8uevju6lq.apps.googleusercontent.com';
const _kGoogleClientSecret =
    String.fromEnvironment('UDESK_GOOGLE_CLIENT_SECRET');
const _kFirebaseApiKey = 'AIzaSyCxmHe1Y18OWlT6Uj3NaMXCUhywWJFp-2w';

const _kOptEmail = 'udesk-user-email';
const _kOptName = 'udesk-user-name';
const _kOptUid = 'udesk-user-uid';
const _kOptRefreshToken = 'udesk-refresh-token';

class UdeskAuth {
  static final email = ''.obs;
  static final name = ''.obs;
  static final uid = ''.obs;
  static final busy = false.obs;

  static bool get signedIn => uid.value.isNotEmpty;

  // UDesk super-admin: a fresh Firebase ID token (for the OTP worker to verify the admin).
  static Future<String?> idToken() async {
    try {
      final refresh = bind.mainGetLocalOption(key: _kOptRefreshToken);
      if (refresh.isEmpty) return null;
      final resp = await http
          .post(
            Uri.https('securetoken.googleapis.com', '/v1/token',
                {'key': _kFirebaseApiKey}),
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: 'grant_type=refresh_token&refresh_token=$refresh',
          )
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) return null;
      final j = jsonDecode(resp.body);
      // Keep the rotated refresh token.
      final nr = '${j['refresh_token'] ?? ''}';
      if (nr.isNotEmpty) {
        await bind.mainSetLocalOption(key: _kOptRefreshToken, value: nr);
      }
      return j['id_token'] as String?;
    } catch (e) {
      debugPrint('UDesk auth: idToken failed: $e');
      return null;
    }
  }

  static void load() {
    email.value = bind.mainGetLocalOption(key: _kOptEmail);
    name.value = bind.mainGetLocalOption(key: _kOptName);
    uid.value = bind.mainGetLocalOption(key: _kOptUid);
  }

  static Future<void> _save(
      String email_, String name_, String uid_, String refreshToken) async {
    await bind.mainSetLocalOption(key: _kOptEmail, value: email_);
    await bind.mainSetLocalOption(key: _kOptName, value: name_);
    await bind.mainSetLocalOption(key: _kOptUid, value: uid_);
    await bind.mainSetLocalOption(key: _kOptRefreshToken, value: refreshToken);
    email.value = email_;
    name.value = name_;
    uid.value = uid_;
  }

  static Future<void> signOut() => _save('', '', '', '');

  static String _random(int length) {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final rnd = Random.secure();
    return List.generate(length, (_) => chars[rnd.nextInt(chars.length)])
        .join();
  }

  /// Returns null on success, otherwise a message to show the user.
  static Future<String?> signIn() async {
    if (busy.value) return null;
    if (_kGoogleClientSecret.isEmpty) {
      debugPrint('UDesk sign-in: built without UDESK_GOOGLE_CLIENT_SECRET');
      return 'Failed';
    }
    busy.value = true;
    HttpServer? server;
    try {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final redirectUri = 'http://127.0.0.1:${server.port}';
      final verifier = _random(64);
      final challenge = base64Url
          .encode(sha256.convert(ascii.encode(verifier)).bytes)
          .replaceAll('=', '');
      final state = _random(32);

      final authUrl = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
        'client_id': _kGoogleClientId,
        'redirect_uri': redirectUri,
        'response_type': 'code',
        'scope': 'openid email profile',
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
        'state': state,
        'prompt': 'select_account',
      });
      if (!await launchUrl(authUrl, mode: LaunchMode.externalApplication)) {
        return 'Failed to open the browser';
      }

      String? code;
      String? error;
      await for (final request
          in server.timeout(const Duration(minutes: 3), onTimeout: (sink) {
        sink.close();
      })) {
        final params = request.uri.queryParameters;
        if (params['state'] != state) {
          request.response.statusCode = HttpStatus.badRequest;
          await request.response.close();
          continue;
        }
        code = params['code'];
        error = params['error'];
        request.response.headers.contentType = ContentType.html;
        request.response.write(_resultPage(code != null));
        await request.response.close();
        break;
      }
      await server.close(force: true);
      server = null;
      if (code == null) {
        return error == null ? 'Timeout' : 'Cancelled';
      }

      final tokenResp = await http
          .post(Uri.https('oauth2.googleapis.com', '/token'), body: {
        'code': code,
        'client_id': _kGoogleClientId,
        'client_secret': _kGoogleClientSecret,
        'redirect_uri': redirectUri,
        'grant_type': 'authorization_code',
        'code_verifier': verifier,
      });
      final idToken = jsonDecode(tokenResp.body)['id_token'];
      if (tokenResp.statusCode != 200 || idToken is! String) {
        debugPrint('UDesk sign-in: token exchange ${tokenResp.statusCode}');
        return 'Failed';
      }

      final fbResp = await http.post(
          Uri.https('identitytoolkit.googleapis.com',
              '/v1/accounts:signInWithIdp', {'key': _kFirebaseApiKey}),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'postBody': 'id_token=$idToken&providerId=google.com',
            'requestUri': 'http://localhost',
            'returnSecureToken': true,
          }));
      final fb = jsonDecode(fbResp.body);
      if (fbResp.statusCode != 200 || fb['localId'] is! String) {
        debugPrint(
            'UDesk sign-in: firebase ${fbResp.statusCode} ${fb['error']?['message']}');
        return 'Failed';
      }
      await _save(fb['email'] ?? '', fb['displayName'] ?? '', fb['localId'],
          fb['refreshToken'] ?? '');
      return null;
    } catch (e) {
      debugPrint('UDesk sign-in: $e');
      return 'Failed';
    } finally {
      await server?.close(force: true);
      busy.value = false;
    }
  }

  static String _resultPage(bool ok) {
    final title = ok ? 'เข้าสู่ระบบสำเร็จ' : 'เข้าสู่ระบบไม่สำเร็จ';
    final body = ok
        ? 'กลับไปที่ UDesk ได้เลย ปิดหน้านี้ได้'
        : 'กลับไปที่ UDesk แล้วลองใหม่อีกครั้ง';
    return '<!doctype html><html lang="th"><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width,initial-scale=1">'
        '<title>UDesk</title>'
        '<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Anuphan:wght@400;600&display=swap">'
        '<body style="margin:0;height:100vh;display:grid;place-items:center;'
        'font-family:Anuphan,Leelawadee UI,Tahoma,sans-serif;background:#071a4d;color:#fff">'
        '<div style="text-align:center"><h1 style="font-weight:600">$title</h1>'
        '<p style="color:#c9d8ff">$body</p></div></body></html>';
  }
}

/// The Account section of Settings: one Google button, or the signed-in user.
Widget udeskAccount(BuildContext context) {
  UdeskAuth.load();
  return Obx(() {
    if (UdeskAuth.signedIn) {
      final label =
          UdeskAuth.name.value.isEmpty ? UdeskAuth.email.value : UdeskAuth.name.value;
      return Row(children: [
        CircleAvatar(
          radius: 20,
          backgroundColor: MyTheme.accent,
          child: Text(label.isEmpty ? '?' : label.characters.first.toUpperCase(),
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w600)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600)),
              Text(UdeskAuth.email.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        OutlinedButton(
            onPressed: UdeskAuth.signOut, child: Text(translate('Logout'))),
      ]).marginOnly(left: 15, bottom: 6);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('ไม่เข้าสู่ระบบก็ใช้งาน UDesk ได้ตามปกติ',
          style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 10),
      ElevatedButton.icon(
        onPressed: UdeskAuth.busy.value
            ? null
            : () async {
                final err = await UdeskAuth.signIn();
                if (err != null) {
                  showToast(translate(err));
                }
              },
        icon: UdeskAuth.busy.value
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.login_rounded, size: 18),
        label: Text(UdeskAuth.busy.value
            ? 'กำลังรอการยืนยันในเบราว์เซอร์'
            : 'เข้าสู่ระบบด้วย Google'),
      ),
    ]).marginOnly(left: 15, bottom: 6);
  });
}

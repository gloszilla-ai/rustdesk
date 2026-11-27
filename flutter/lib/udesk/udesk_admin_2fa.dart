import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/udesk/udesk_auth.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;

// UDesk super-admin 2FA. Before the admin tool can sign (and thus silently control machines),
// the admin must pass a second factor: a one-time code emailed by the OTP worker. On success the
// worker returns the admin private key, which is handed to Rust in memory only (main_set_common).
// Without this, the admin tool holds no key and behaves like a normal client.
const String _kWorkerUrl = String.fromEnvironment('UDESK_OTP_WORKER_URL');

class UdeskAdmin2FA {
  static final unlocked = false.obs;
  static final busy = false.obs;
  static final error = ''.obs;

  static bool get configured => kUdeskAdminTool && _kWorkerUrl.isNotEmpty;

  static bool _th() {
    final lang = bind.mainGetLocalOption(key: 'lang');
    return lang.isEmpty || lang == 'th';
  }

  static Future<bool> _requestOtp() async {
    final token = await UdeskAuth.idToken();
    if (token == null) {
      error.value = _th()
          ? 'ต้องเข้าสู่ระบบด้วยบัญชีแอดมินก่อน'
          : 'Sign in with the admin account first';
      return false;
    }
    final resp = await http
        .post(Uri.parse('$_kWorkerUrl/request-otp'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'idToken': token}))
        .timeout(const Duration(seconds: 20));
    if (resp.statusCode == 200) return true;
    error.value = _th() ? 'ส่งรหัสไม่สำเร็จ' : 'Could not send the code';
    return false;
  }

  static Future<bool> _verifyOtp(String otp) async {
    final token = await UdeskAuth.idToken();
    if (token == null) return false;
    final resp = await http
        .post(Uri.parse('$_kWorkerUrl/verify-otp'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'idToken': token, 'otp': otp}))
        .timeout(const Duration(seconds: 20));
    if (resp.statusCode != 200) {
      error.value = _th() ? 'รหัสไม่ถูกต้อง' : 'Wrong code';
      return false;
    }
    final key = '${jsonDecode(resp.body)['key'] ?? ''}';
    if (key.isEmpty) return false;
    // Hand the key to Rust in memory only; it is never persisted.
    bind.mainSetCommon(key: 'udesk-admin-key', value: key);
    unlocked.value = true;
    return true;
  }

  static void lock() {
    unlocked.value = false;
    bind.mainSetCommon(key: 'udesk-admin-key', value: '');
  }

  /// Returns true if the admin key is available (already unlocked, or unlocked via the dialog).
  /// For a non-admin build, or when 2FA is not configured, returns false without prompting.
  static Future<bool> ensureUnlocked(BuildContext context) async {
    if (!kUdeskAdminTool) return false;
    if (unlocked.value) return true;
    if (!configured) {
      error.value = _th()
          ? 'ยังไม่ได้ตั้งค่า OTP (UDESK_OTP_WORKER_URL)'
          : '2FA worker is not configured';
      return false;
    }
    error.value = '';
    busy.value = true;
    final sent = await _requestOtp();
    busy.value = false;
    if (!sent) {
      await _show(context, canResend: false);
      return unlocked.value;
    }
    await _show(context, canResend: true);
    return unlocked.value;
  }

  static Future<void> _show(BuildContext context,
      {required bool canResend}) async {
    final controller = TextEditingController();
    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        title: Text(_th() ? 'ยืนยันแอดมิน (OTP)' : 'Admin verification'),
        content: SizedBox(
          width: 320,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_th()
                ? 'กรอกรหัสที่ส่งไปยังอีเมลแอดมิน'
                : 'Enter the code sent to the admin email'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
            Obx(() => error.value.isEmpty
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(error.value,
                        style: const TextStyle(color: Colors.red)))),
          ]),
        ),
        actions: [
          if (canResend)
            TextButton(
              onPressed: () async {
                error.value = '';
                await _requestOtp();
              },
              child: Text(_th() ? 'ส่งรหัสใหม่' : 'Resend'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(_th() ? 'ยกเลิก' : 'Cancel'),
          ),
          Obx(() => ElevatedButton(
                onPressed: busy.value
                    ? null
                    : () async {
                        busy.value = true;
                        final ok = await _verifyOtp(controller.text.trim());
                        busy.value = false;
                        if (ok && ctx.mounted) Navigator.pop(ctx);
                      },
                child: Text(_th() ? 'ยืนยัน' : 'Verify'),
              )),
        ],
      ),
    );
  }
}

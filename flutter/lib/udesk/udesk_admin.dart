import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/models/platform_model.dart';

// UDesk admin build (office endpoints). When UDESK_ADMIN is baked in, the machine accepts
// the admin's connections silently: unattended with a permanent password and auto-accept,
// and the connection-manager window stays hidden (see ServerModel.hideCm). The controlling
// (admin) machine uses the NORMAL build and just connects out — it never sets UDESK_ADMIN.
//
// Access is still recorded centrally (UdeskLog) for accountability; "silent" means the
// person at the office machine sees no prompt, not that the access is untracked.
class UdeskAdmin {
  static bool _done = false;

  static void bootstrap() {
    if (!kUdeskAdmin || !isDesktop || _done) return;
    _done = true;
    // Unattended + auto-accept. These are local config, so they apply at once and
    // self-heal on every launch if someone changes them on the machine.
    bind.mainSetOption(key: kOptionApproveMode, value: 'password');
    bind.mainSetOption(
        key: kOptionVerificationMethod, value: 'use-permanent-password');
    if (kUdeskAdminPassword.isEmpty) return;
    // Setting the permanent password goes through the background service; retry a few
    // times in case the service has not finished starting yet.
    () async {
      for (var i = 0; i < 10; i++) {
        try {
          final ok = await bind
              .mainSetPermanentPasswordWithResult(password: kUdeskAdminPassword);
          if (ok) return;
        } catch (e) {
          debugPrint('UDesk admin: set password attempt $i failed: $e');
        }
        await Future.delayed(const Duration(seconds: 2));
      }
      debugPrint('UDesk admin: could not set permanent password');
    }();
  }
}

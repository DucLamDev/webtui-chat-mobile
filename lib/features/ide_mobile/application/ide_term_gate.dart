import 'dart:async';

import '../domain/ide_device_security.dart';

enum IdeTermAuth { ok, cancelled, unavailable }

/// Hỏi vân tay / khoá màn hình cục bộ trước khi mở hoặc gắn terminal. Luôn
/// hỏi (không dùng lại lần mở khoá IDE): terminal là quyền chạy lệnh.
Future<IdeTermAuth> askTermFingerprint(
  IdeDeviceSecurity security, {
  required String reason,
  Duration timeout = const Duration(seconds: 90),
}) async {
  try {
    final result = await security
        .authenticateDeviceOwner(reason)
        .timeout(timeout);
    return switch (result) {
      DeviceOwnerAuthResult.ok => IdeTermAuth.ok,
      DeviceOwnerAuthResult.cancelled => IdeTermAuth.cancelled,
      _ => IdeTermAuth.unavailable,
    };
  } on Object {
    return IdeTermAuth.unavailable;
  }
}

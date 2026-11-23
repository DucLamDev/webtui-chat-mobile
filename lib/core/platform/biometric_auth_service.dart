import 'dart:convert';

import 'package:flutter/services.dart';

import '../../l10n/app_strings.dart';

/// Kết quả hỏi vân tay / mã khoá màn hình của máy.
enum DeviceOwnerAuthResult { ok, cancelled, notEnrolled, unavailable }

/// Lỗi khi tạo / dùng khoá xác nhận trong chip bảo mật.
final class StepKeyException implements Exception {
  const StepKeyException(this.code);

  /// `cancelled | notEnrolled | key_missing | key_invalid | unavailable`.
  final String code;

  bool get cancelled => code == 'cancelled';

  @override
  String toString() => 'StepKeyException($code)';
}

final class BiometricAuthService {
  const BiometricAuthService();

  static const _channel = MethodChannel('webtui/biometric');

  Future<bool> isAvailable() async {
    try {
      return await _channel.invokeMethod<bool>('isAvailable') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> authenticate({String? reason}) async {
    try {
      return await _channel.invokeMethod<bool>('authenticate', {
            'reason':
                reason ??
                tr(
                  'Xác thực để mở khóa WebTUI Chat',
                  'Authenticate to unlock WebTUI Chat',
                ),
          }) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Hỏi chủ máy bằng vân tay / khuôn mặt hoặc mã khoá màn hình.
  Future<DeviceOwnerAuthResult> authenticateDeviceOwner(String reason) async {
    try {
      final value = await _channel.invokeMethod<String>(
        'authenticateDeviceOwner',
        {'reason': reason},
      );
      return switch (value) {
        'ok' => DeviceOwnerAuthResult.ok,
        'cancelled' => DeviceOwnerAuthResult.cancelled,
        'notEnrolled' => DeviceOwnerAuthResult.notEnrolled,
        _ => DeviceOwnerAuthResult.unavailable,
      };
    } on MissingPluginException {
      return DeviceOwnerAuthResult.unavailable;
    } on PlatformException {
      return DeviceOwnerAuthResult.unavailable;
    }
  }

  /// Tạo khoá ký P-256 trong chip bảo mật (mỗi lần ký phải xác nhận). Trả
  /// khoá công khai SPKI DER base64.
  Future<String> createStepKey(String alias) async {
    try {
      final value = await _channel.invokeMethod<String>('createStepKey', {
        'alias': alias,
      });
      if (value == null || value.isEmpty) {
        throw const StepKeyException('unavailable');
      }
      return value;
    } on MissingPluginException {
      throw const StepKeyException('unavailable');
    } on PlatformException catch (error) {
      throw StepKeyException(_stepCode(error));
    }
  }

  /// Mili giây của đồng hồ máy tính cả lúc ngủ, không chỉnh được (Android
  /// `elapsedRealtime`, iOS `CLOCK_MONOTONIC`). `null` nếu không đọc được.
  Future<int?> uptimeMs() async {
    try {
      return await _channel.invokeMethod<int>('uptimeMs');
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// Xoá khoá xác nhận [alias] (không có thì thôi). Ném [StepKeyException].
  Future<void> deleteStepKey(String alias) async {
    try {
      await _channel.invokeMethod<void>('deleteStepKey', {'alias': alias});
    } on MissingPluginException {
      throw const StepKeyException('unavailable');
    } on PlatformException catch (error) {
      throw StepKeyException(_stepCode(error));
    }
  }

  /// Ký [data] bằng khoá xác nhận; máy hiện hộp vân tay với lời [reason].
  /// Trả chữ ký DER ECDSA-SHA256 base64.
  Future<String> signWithStepKey({
    required String alias,
    required List<int> data,
    required String reason,
  }) async {
    try {
      final value = await _channel.invokeMethod<String>('signWithStepKey', {
        'alias': alias,
        'data': base64Encode(data),
        'reason': reason,
      });
      if (value == null || value.isEmpty) {
        throw const StepKeyException('unavailable');
      }
      return value;
    } on MissingPluginException {
      throw const StepKeyException('unavailable');
    } on PlatformException catch (error) {
      throw StepKeyException(_stepCode(error));
    }
  }

  static String _stepCode(PlatformException error) => switch (error.code) {
    'cancelled' ||
    'notEnrolled' ||
    'key_missing' ||
    'key_invalid' ||
    'unsupported' ||
    'biometricRequired' => error.code,
    _ => 'unavailable',
  };
}

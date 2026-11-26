import 'dart:convert';

import 'package:flutter/services.dart';

import '../../l10n/app_strings.dart';

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

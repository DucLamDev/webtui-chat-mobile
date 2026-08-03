import 'package:flutter/services.dart';

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

  Future<bool> authenticate({
    String reason = 'Xác thực để mở khóa WebTui Chat',
  }) async {
    try {
      return await _channel.invokeMethod<bool>('authenticate', {
            'reason': reason,
          }) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}

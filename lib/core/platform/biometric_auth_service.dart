import 'package:flutter/services.dart';

import '../../l10n/app_strings.dart';

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
}

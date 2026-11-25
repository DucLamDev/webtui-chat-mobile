import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../../core/platform/biometric_auth_service.dart';
import '../../../l10n/app_strings.dart';
import '../domain/ide_web_device_key.dart';
import '../domain/ide_web_ports.dart';

/// Chip khoá: "possession" qua kênh `webtui/ide_web_keys`, "biometric" dùng lại
/// kênh `webtui/biometric` sẵn có (mỗi lần ký hỏi sinh trắc mạnh).
final class MethodChannelIdeWebKeyChip implements IdeWebKeyChip {
  const MethodChannelIdeWebKeyChip({
    BiometricAuthService biometric = const BiometricAuthService(),
    MethodChannel channel = const MethodChannel('webtui/ide_web_keys'),
  }) : _biometric = biometric,
       _channel = channel;

  final BiometricAuthService _biometric;
  final MethodChannel _channel;

  @override
  Future<IdeWebCreatedKey> create(
    IdeWebKeyPurpose purpose,
    String alias,
  ) => _run(() async {
    if (purpose == IdeWebKeyPurpose.biometric) {
      // iOS dọn khoá của bản cài trước ở lần gọi đầu của kênh mới: phải chạy
      // trước khi kênh cũ tạo khoá, không thì khoá vừa tạo bị dọn theo.
      await isUsable(purpose, alias);
      final publicKey = await _biometric.createStepKey(alias);
      return IdeWebCreatedKey(
        publicKey: ideWebBase64Url(
          base64.decode(base64.normalize(publicKey.replaceAll('\n', ''))),
        ),
        hardware: await _hardwareOf(alias),
      );
    }
    final value = await _channel.invokeMapMethod<String, Object?>(
      'createPossessionKey',
      {'alias': alias},
    );
    final publicKey = value?['publicKey'];
    final hardware = value?['hardware'];
    if (publicKey is! String ||
        publicKey.isEmpty ||
        hardware is! String ||
        !const {'strongbox', 'tee', 'secure_enclave'}.contains(hardware)) {
      throw const IdeWebKeyException('failed');
    }
    return IdeWebCreatedKey(publicKey: publicKey, hardware: hardware);
  });

  /// Kênh cũ chỉ nhận khoá trong phần cứng nhưng không báo loại nào: hỏi kênh
  /// mới; không đọc được thì báo loại thấp nhất kênh cũ bảo đảm.
  Future<String> _hardwareOf(String alias) async {
    Object? hardware;
    try {
      final state = await _channel.invokeMapMethod<String, Object?>(
        'keyState',
        {'alias': alias},
      );
      hardware = state?['hardware'];
    } on MissingPluginException {
      hardware = null;
    } on PlatformException {
      hardware = null;
    }
    if (hardware is String && hardware.isNotEmpty) return hardware;
    return defaultTargetPlatform == TargetPlatform.iOS
        ? 'secure_enclave'
        : 'tee';
  }

  @override
  Future<Uint8List> sign(
    IdeWebKeyPurpose purpose,
    String alias,
    Uint8List data,
  ) => _run(() async {
    if (purpose == IdeWebKeyPurpose.biometric) {
      final signature = await _biometric.signWithStepKey(
        alias: alias,
        data: data,
        reason: tr('Xác nhận trong VPSTTT IDE', 'Confirm in VPSTTT IDE'),
      );
      return base64.decode(base64.normalize(signature.replaceAll('\n', '')));
    }
    final signature = await _channel.invokeMethod<Uint8List>('signPossession', {
      'alias': alias,
      'data': data,
    });
    if (signature == null || signature.isEmpty) {
      throw const IdeWebKeyException('failed');
    }
    return signature;
  });

  @override
  Future<bool> isUsable(IdeWebKeyPurpose purpose, String alias) async {
    // iOS: khoá sinh trắc chỉ biết mất hiệu lực khi ký (`key_invalid`).
    try {
      final value = await _channel.invokeMapMethod<String, Object?>(
        'keyState',
        {'alias': alias},
      );
      return value?['exists'] == true && value?['usable'] == true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<void> delete(IdeWebKeyPurpose purpose, String alias) => _run(() async {
    if (purpose == IdeWebKeyPurpose.biometric) {
      await _biometric.deleteStepKey(alias);
    } else {
      await _channel.invokeMethod<void>('deleteKey', {'alias': alias});
    }
  });

  // Kênh `webtui/biometric` tính cả sinh trắc yếu nên không dùng ở đây.
  @override
  Future<IdeWebBiometricState> biometricState() async {
    try {
      final value = await _channel.invokeMapMethod<String, Object?>(
        'biometricState',
      );
      return IdeWebBiometricState(
        available: value?['available'] == true,
        enrolled: value?['enrolled'] == true,
        strong: value?['strong'] == true,
      );
    } on MissingPluginException {
      return IdeWebBiometricState.none;
    } on PlatformException {
      return IdeWebBiometricState.none;
    }
  }

  static Future<T> _run<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on IdeWebKeyException {
      rethrow;
    } on StepKeyException catch (error) {
      throw IdeWebKeyException(switch (error.code) {
        'notEnrolled' || 'biometricRequired' => 'not_enrolled',
        'cancelled' ||
        'key_missing' ||
        'key_invalid' ||
        'unsupported' => error.code,
        _ => 'failed',
      });
    } on MissingPluginException {
      throw const IdeWebKeyException('unsupported');
    } on PlatformException catch (error) {
      throw IdeWebKeyException(switch (error.code) {
        'unsupported' || 'key_missing' || 'key_invalid' => error.code,
        _ => 'failed',
      });
    } on FormatException {
      throw const IdeWebKeyException('failed');
    }
  }
}

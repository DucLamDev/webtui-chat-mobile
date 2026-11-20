import '../../../core/platform/biometric_auth_service.dart';
import '../domain/ide_device_security.dart';

/// [IdeDeviceSecurity] dùng kênh native `webtui/biometric`.
final class BiometricIdeDeviceSecurity implements IdeDeviceSecurity {
  const BiometricIdeDeviceSecurity(this._service);

  final BiometricAuthService _service;

  @override
  Future<DeviceOwnerAuthResult> authenticateDeviceOwner(String reason) =>
      _service.authenticateDeviceOwner(reason);

  @override
  Future<String> createStepKey(String alias) => _service.createStepKey(alias);

  @override
  Future<int?> uptimeMs() => _service.uptimeMs();

  @override
  Future<void> deleteStepKey(String alias) => _service.deleteStepKey(alias);

  @override
  Future<String> signWithStepKey({
    required String alias,
    required List<int> data,
    required String reason,
  }) => _service.signWithStepKey(alias: alias, data: data, reason: reason);
}

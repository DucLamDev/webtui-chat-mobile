import '../../../core/platform/biometric_auth_service.dart';

export '../../../core/platform/biometric_auth_service.dart'
    show DeviceOwnerAuthResult, StepKeyException;

/// Cầu nối tới kênh `webtui/biometric` (có bản giả trong test).
abstract interface class IdeDeviceSecurity {
  Future<DeviceOwnerAuthResult> authenticateDeviceOwner(String reason);

  /// SPKI DER (P-256) base64. Ném [StepKeyException].
  Future<String> createStepKey(String alias);

  /// Mili giây của đồng hồ máy tính cả lúc ngủ, không chỉnh được; `null` nếu
  /// không đọc được (khi đó coi như đã quá hạn).
  Future<int?> uptimeMs();

  /// Xoá khoá xác nhận [alias]. Ném [StepKeyException].
  Future<void> deleteStepKey(String alias);

  /// Chữ ký DER ECDSA-SHA256 base64 sau khi người dùng xác nhận. Ném
  /// [StepKeyException].
  Future<String> signWithStepKey({
    required String alias,
    required List<int> data,
    required String reason,
  });
}

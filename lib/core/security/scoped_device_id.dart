import 'package:uuid/uuid.dart';

import 'secure_key_value_store.dart';

/// Mã thiết bị theo từng máy chủ: cùng một bí mật gốc của máy nhưng mỗi
/// instance nhận một mã khác nhau, nên hai máy chủ độc lập không ghép được
/// cùng một thiết bị.
String deriveScopedDeviceId({
  required String masterSecret,
  required String instanceStorageId,
  Uuid uuid = const Uuid(),
}) {
  return uuid.v5(Namespace.url.value, '$masterSecret:$instanceStorageId');
}

/// Đọc mã thiết bị đang dùng mà không tạo bí mật gốc mới (dùng ở isolate nền
/// và các bước so sánh: chưa có bí mật thì coi như chưa biết mã máy).
Future<String?> readScopedDeviceId(
  SecureKeyValueStore store, {
  required String instanceStorageId,
}) async {
  final scopeId = instanceStorageId.trim();
  if (scopeId.isEmpty) return null;
  try {
    final masterSecret = await store.read(SecureStoreKey.deviceMasterSecret);
    if (masterSecret == null || masterSecret.trim().isEmpty) return null;
    return deriveScopedDeviceId(
      masterSecret: masterSecret,
      instanceStorageId: scopeId,
    );
  } on Object {
    return null;
  }
}

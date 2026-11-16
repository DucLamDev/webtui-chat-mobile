import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';

/// Kho khoá của bản Linux chạy thử: giữ trong bộ nhớ, không ghi ra đĩa.
/// Tắt app hoặc khởi động lại (restart) là mất, phải đăng nhập lại.
class FlutterSecureStorageLinuxPreview extends FlutterSecureStoragePlatform {
  static void registerWith() {
    FlutterSecureStoragePlatform.instance = FlutterSecureStorageLinuxPreview();
  }

  final Map<String, String> _values = <String, String>{};

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {
    _values[key] = value;
  }

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async =>
      _values[key];

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async =>
      _values.containsKey(key);

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async {
    _values.remove(key);
  }

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async =>
      Map<String, String>.of(_values);

  @override
  Future<void> deleteAll({required Map<String, String> options}) async {
    _values.clear();
  }
}

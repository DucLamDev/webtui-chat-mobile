import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/security/secure_key_value_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'clearSession xoá cả khoá máy IDE, giữ nguyên khoá không thuộc phiên',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        SecureStoreKey.ideDevice.value: '{"x":1}',
        SecureStoreKey.accessToken.value: 'token',
      });
      const store = FlutterSecureKeyValueStore(FlutterSecureStorage());
      await store.clearSession();
      expect(await store.read(SecureStoreKey.ideDevice), isNull);
      expect(await store.read(SecureStoreKey.accessToken), isNull);
    },
  );

  test('khoá máy IDE ghi / đọc / xoá ở chế độ chỉ máy này (iOS)', () async {
    final storage = _RecordingStorage();
    final store = FlutterSecureKeyValueStore(storage);
    await store.write(SecureStoreKey.ideDevice, 'x');
    await store.read(SecureStoreKey.ideDevice);
    await store.delete(SecureStoreKey.ideDevice);
    await store.clearSession();
    final ide = storage.calls.where(
      (c) => c.key == SecureStoreKey.ideDevice.value,
    );
    expect(ide, hasLength(4));
    for (final call in ide) {
      expect(
        call.ios?.accessibility,
        KeychainAccessibility.unlocked_this_device,
        reason: call.op,
      );
    }
    final token = storage.calls.firstWhere(
      (c) => c.key == SecureStoreKey.accessToken.value,
    );
    expect(token.ios, isNull, reason: 'khoá khác giữ chế độ cũ');
  });
}

final class _Call {
  _Call(this.op, this.key, this.ios);
  final String op;
  final String key;
  final AppleOptions? ios;
}

class _RecordingStorage extends FlutterSecureStorage {
  _RecordingStorage();

  final calls = <_Call>[];

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    calls.add(_Call('read', key, iOptions));
    return null;
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    calls.add(_Call('write', key, iOptions));
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    calls.add(_Call('delete', key, iOptions));
  }
}

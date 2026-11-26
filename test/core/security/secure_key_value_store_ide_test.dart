import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/security/secure_key_value_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'clearSession xoá cả khoá máy IDE, giữ nguyên khoá không thuộc phiên',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        SecureStoreKey.legacyIdeDevice.value: '{"x":1}',
        SecureStoreKey.accessToken.value: 'token',
      });
      const store = FlutterSecureKeyValueStore(FlutterSecureStorage());
      await store.clearSession();
      expect(await store.read(SecureStoreKey.legacyIdeDevice), isNull);
      expect(await store.read(SecureStoreKey.accessToken), isNull);
    },
  );

  test('deleteRetiredKeys xoá khoá IDE native cũ, giữ khoá khác', () async {
    FlutterSecureStorage.setMockInitialValues({
      SecureStoreKey.legacyIdeDevice.value: '{"x":1}',
      SecureStoreKey.legacyIdeClientId.value: 'mobile-1',
      SecureStoreKey.accessToken.value: 'token',
      SecureStoreKey.ideWebDevice.value: '{"y":1}',
    });
    const store = FlutterSecureKeyValueStore(FlutterSecureStorage());
    await store.deleteRetiredKeys();
    await store.deleteRetiredKeys();
    expect(await store.read(SecureStoreKey.legacyIdeDevice), isNull);
    expect(await store.read(SecureStoreKey.legacyIdeClientId), isNull);
    expect(await store.read(SecureStoreKey.accessToken), 'token');
    expect(await store.read(SecureStoreKey.ideWebDevice), '{"y":1}');
  });

  test(
    'deleteRetiredKeys xoá khoá máy cũ ở đúng chế độ keychain (iOS)',
    () async {
      final storage = _RecordingStorage();
      final store = FlutterSecureKeyValueStore(storage);
      await store.deleteRetiredKeys();
      final device = storage.calls.singleWhere(
        (c) => c.key == SecureStoreKey.legacyIdeDevice.value,
      );
      expect(device.op, 'delete');
      expect(
        device.ios?.accessibility,
        KeychainAccessibility.unlocked_this_device,
      );
      final clientId = storage.calls.singleWhere(
        (c) => c.key == SecureStoreKey.legacyIdeClientId.value,
      );
      expect(clientId.ios, isNull, reason: 'mã máy cũ ghi ở chế độ mặc định');
    },
  );

  test('khoá máy IDE ghi / đọc / xoá ở chế độ chỉ máy này (iOS)', () async {
    final storage = _RecordingStorage();
    final store = FlutterSecureKeyValueStore(storage);
    await store.write(SecureStoreKey.legacyIdeDevice, 'x');
    await store.read(SecureStoreKey.legacyIdeDevice);
    await store.delete(SecureStoreKey.legacyIdeDevice);
    await store.clearSession();
    final ide = storage.calls.where(
      (c) => c.key == SecureStoreKey.legacyIdeDevice.value,
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

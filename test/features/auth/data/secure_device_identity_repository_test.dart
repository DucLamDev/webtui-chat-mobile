import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/security/instance_scope.dart';
import 'package:webtui_chat/core/security/secure_key_value_store.dart';
import 'package:webtui_chat/features/auth/data/repositories/secure_device_identity_repository.dart';

void main() {
  test(
    'device ID is stable per instance and unlinkable across instances',
    () async {
      final store = _MemorySecureStore();
      var activeInstance = _instanceA;
      final repository = SecureDeviceIdentityRepository(
        secureStore: store,
        loadInstanceScope: () => activeInstance,
      );

      final firstA = await repository.currentDevice();
      final secondA = await repository.currentDevice();
      activeInstance = _instanceB;
      final firstB = await repository.currentDevice();

      expect(firstA.id, secondA.id);
      expect(firstB.id, isNot(firstA.id));
      expect(firstA.displayName, startsWith('Ứng dụng chat'));
      expect(await store.read(SecureStoreKey.deviceMasterSecret), isNotEmpty);
      expect(await store.read(SecureStoreKey.deviceId), isNull);
    },
  );
}

final _instanceA = InstanceScope(
  instanceId: '11111111-1111-4111-8111-111111111111',
  serverOrigin: Uri.parse('https://one.example'),
);

final _instanceB = InstanceScope(
  instanceId: '22222222-2222-4222-8222-222222222222',
  serverOrigin: Uri.parse('https://two.example'),
);

final class _MemorySecureStore implements SecureKeyValueStore {
  final Map<SecureStoreKey, String> _values = {};

  @override
  Future<String?> read(SecureStoreKey key) async => _values[key];

  @override
  Future<void> write(SecureStoreKey key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> delete(SecureStoreKey key) async {
    _values.remove(key);
  }

  @override
  Future<void> clearSession() async {}
}

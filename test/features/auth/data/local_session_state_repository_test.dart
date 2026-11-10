import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/database/app_database.dart';
import 'package:webtui_chat/core/security/instance_scope.dart';
import 'package:webtui_chat/core/security/secure_key_value_store.dart';
import 'package:webtui_chat/features/auth/data/repositories/local_session_state_repository.dart';
import 'package:webtui_chat/features/auth/domain/repositories/auth_token_repository.dart';

void main() {
  final instance = InstanceScope(
    instanceId: '11111111-1111-4111-8111-111111111111',
    serverOrigin: Uri.parse('https://chat.example.com'),
  );
  final scope = '${instance.storagePrefix}messages';

  test(
    'thu hồi cũ không xoá Drift của lần đăng nhập mới cùng máy chủ',
    () async {
      final database = AppDatabase(createInMemoryDriftConnection());
      addTearDown(database.close);
      await database.putKeyValue(scope: scope, key: 'message', value: 'mới');
      final store = _Store()
        ..values.addAll({
          SecureStoreKey.activeInstanceScopeId: instance.storageId,
          SecureStoreKey.activeInstanceGeneration: 'new',
          SecureStoreKey.accessToken: 'new-token',
        });
      final repository = LocalSessionStateRepository(
        secureStore: store,
        database: database,
        loadInstanceScope: () => instance,
        clearNativeInstanceBinding: () async =>
            fail('Không được xoá phiên mới'),
      );
      expect(
        await repository.resetForLogoutIfCurrent(
          AuthTokenMutationGuard(
            instanceScopeId: instance.storageId,
            generation: 'old',
          ),
        ),
        isFalse,
      );
      expect(await database.readKeyValue(scope: scope, key: 'message'), 'mới');
      expect(store.values[SecureStoreKey.accessToken], 'new-token');
    },
  );

  test('lỗi xoá thông báo vẫn xoá tệp, Drift và token', () async {
    final database = AppDatabase(createInMemoryDriftConnection());
    addTearDown(database.close);
    await database.putKeyValue(scope: scope, key: 'message', value: 'bí mật');
    final store = _Store()
      ..values.addAll({
        SecureStoreKey.activeInstanceScopeId: instance.storageId,
        SecureStoreKey.activeInstanceGeneration: 'active',
        SecureStoreKey.accessToken: 'token',
      });
    final calls = <String>[];
    final repository = LocalSessionStateRepository(
      secureStore: store,
      database: database,
      loadInstanceScope: () => instance,
      clearNativeInstanceBinding: () async => calls.add('binding'),
      terminateNativeCalls: (_) async => calls.add('callkit'),
      clearMessageNotifications: () async => throw StateError('plugin error'),
      clearScopedAttachmentFiles: (_) async => calls.add('files'),
    );
    await expectLater(
      repository.resetForLogoutIfCurrent(
        AuthTokenMutationGuard(
          instanceScopeId: instance.storageId,
          generation: 'active',
        ),
      ),
      throwsStateError,
    );
    expect(calls, ['binding', 'callkit', 'files']);
    expect(store.values[SecureStoreKey.accessToken], isNull);
    expect(await database.readKeyValue(scope: scope, key: 'message'), isNull);
  });
}

final class _Store implements SecureKeyValueStore {
  final values = <SecureStoreKey, String>{};
  @override
  Future<String?> read(SecureStoreKey key) async => values[key];
  @override
  Future<void> write(SecureStoreKey key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(SecureStoreKey key) async {
    values.remove(key);
  }

  @override
  Future<void> clearSession() async {
    values.remove(SecureStoreKey.accessToken);
    values.remove(SecureStoreKey.refreshToken);
  }
}

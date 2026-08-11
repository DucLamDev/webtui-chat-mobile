import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const durableSessionPersistenceValue = 'durable_v1';

enum SecureStoreKey {
  accessToken('access_token'),
  refreshToken('refresh_token'),
  deviceId('device_id'),
  deviceMasterSecret('device_master_secret_v2'),
  instanceBaseUrl('instance_base_url'),
  instanceWsBaseUrl('instance_ws_base_url'),
  instanceOrganizationName('instance_organization_name'),
  instanceOrganizationLogoUrl('instance_organization_logo_url'),
  instanceRegistrationMode('instance_registration_mode'),
  instanceAppVersion('instance_app_version'),
  instanceId('instance_id_v1'),
  activeInstanceScopeId('active_instance_scope_id_v2'),
  liveDiscoveryValidatedScopeId('live_discovery_validated_scope_id_v1'),
  activeInstanceGeneration('active_instance_generation_v1'),
  instanceDiscoverySnapshot('instance_discovery_snapshot_v1'),
  sessionInstanceScopeId('session_instance_scope_id_v2'),
  sessionPersistence('session_persistence_v1'),
  activeWorkspaceId('active_workspace_id'),
  activeWorkspaceInstanceScopeId('active_workspace_instance_scope_id_v2'),
  appLockEnabled('app_lock_enabled'),
  appLockPinHash('app_lock_pin_hash'),
  serverAccounts('server_accounts_v1');

  const SecureStoreKey(this.value);

  final String value;
}

abstract interface class SecureKeyValueStore {
  Future<String?> read(SecureStoreKey key);
  Future<void> write(SecureStoreKey key, String value);
  Future<void> delete(SecureStoreKey key);
  Future<void> clearSession();
}

final class FlutterSecureKeyValueStore implements SecureKeyValueStore {
  const FlutterSecureKeyValueStore(this._storage);

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(SecureStoreKey key) {
    return _storage.read(key: key.value);
  }

  @override
  Future<void> write(SecureStoreKey key, String value) {
    return _storage.write(key: key.value, value: value);
  }

  @override
  Future<void> delete(SecureStoreKey key) {
    return _storage.delete(key: key.value);
  }

  @override
  Future<void> clearSession() async {
    await Future.wait([
      delete(SecureStoreKey.accessToken),
      delete(SecureStoreKey.refreshToken),
      delete(SecureStoreKey.sessionInstanceScopeId),
      delete(SecureStoreKey.sessionPersistence),
      delete(SecureStoreKey.activeWorkspaceId),
      delete(SecureStoreKey.activeWorkspaceInstanceScopeId),
    ]);
  }
}

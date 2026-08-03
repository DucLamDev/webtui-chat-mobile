import 'package:flutter_secure_storage/flutter_secure_storage.dart';

enum SecureStoreKey {
  accessToken('access_token'),
  refreshToken('refresh_token'),
  deviceId('device_id'),
  instanceBaseUrl('instance_base_url'),
  instanceWsBaseUrl('instance_ws_base_url'),
  instanceOrganizationName('instance_organization_name'),
  instanceOrganizationLogoUrl('instance_organization_logo_url'),
  instanceRegistrationMode('instance_registration_mode'),
  instanceAppVersion('instance_app_version'),
  activeWorkspaceId('active_workspace_id'),
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
      delete(SecureStoreKey.activeWorkspaceId),
    ]);
  }
}

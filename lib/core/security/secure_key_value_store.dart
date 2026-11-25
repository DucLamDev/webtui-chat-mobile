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
  appLockIdleMinutes('app_lock_idle_minutes'),
  serverAccounts('server_accounts_v1'),
  // Khoá thiết bị gắn IDE; đăng xuất gỡ gắn (xoá cùng phiên).
  ideDevice('ide_device_v1'),
  // Mã máy (`mobile-<uuid>`) báo cho phiên AI của IDE; giữ cố định theo máy.
  ideClientId('ide_client_id_v1'),
  // Lượt mở VPSTTT IDE (WebView) đang chờ trình duyệt; xoá cùng phiên.
  ideWebPending('ide_web_pending_v1'),
  // Siêu dữ liệu khoá thiết bị của VPSTTT IDE: GIỮ khi đăng xuất (Smart OTP),
  // xoá khi người khác đăng nhập hoặc xoá tài khoản.
  ideWebDevice('ide_web_device_v1'),
  // WebView của VPSTTT IDE đang giữ dữ liệu của ai / đang chờ xoá.
  ideWebViewData('ide_web_view_data_v1');

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

  /// Khoá gắn IDE chỉ ở máy này: không theo bản sao lưu / iCloud sang iPhone
  /// khác. Đọc, ghi, xoá đều phải cùng chế độ (keychain lọc theo chế độ).
  static const _ideDeviceIos = IOSOptions(
    accessibility: KeychainAccessibility.unlocked_this_device,
  );

  static IOSOptions? _iosOptions(SecureStoreKey key) => switch (key) {
    SecureStoreKey.ideDevice ||
    SecureStoreKey.ideWebPending ||
    SecureStoreKey.ideWebDevice => _ideDeviceIos,
    _ => null,
  };

  @override
  Future<String?> read(SecureStoreKey key) {
    return _storage.read(key: key.value, iOptions: _iosOptions(key));
  }

  @override
  Future<void> write(SecureStoreKey key, String value) {
    return _storage.write(
      key: key.value,
      value: value,
      iOptions: _iosOptions(key),
    );
  }

  @override
  Future<void> delete(SecureStoreKey key) {
    return _storage.delete(key: key.value, iOptions: _iosOptions(key));
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
      delete(SecureStoreKey.ideDevice),
      delete(SecureStoreKey.ideWebPending),
    ]);
  }
}

import 'dart:io';

import 'package:uuid/uuid.dart';

import '../../../../core/security/instance_scope.dart';
import '../../../../core/security/secure_key_value_store.dart';
import '../../domain/entities/device_identity.dart';
import '../../domain/repositories/device_identity_repository.dart';

final class SecureDeviceIdentityRepository implements DeviceIdentityRepository {
  const SecureDeviceIdentityRepository({
    required SecureKeyValueStore secureStore,
    required InstanceScope Function() loadInstanceScope,
    Uuid uuid = const Uuid(),
  }) : _secureStore = secureStore,
       _loadInstanceScope = loadInstanceScope,
       _uuid = uuid;

  final SecureKeyValueStore _secureStore;
  final InstanceScope Function() _loadInstanceScope;
  final Uuid _uuid;

  @override
  Future<DeviceIdentity> currentDevice() async {
    final instanceScope = _loadInstanceScope();
    var masterSecret = await _secureStore.read(
      SecureStoreKey.deviceMasterSecret,
    );
    if (masterSecret == null || masterSecret.trim().isEmpty) {
      // Do not reuse the old global device_id: it may already have been
      // disclosed to multiple independent servers and is therefore linkable.
      masterSecret = _uuid.v4();
      await _secureStore.write(SecureStoreKey.deviceMasterSecret, masterSecret);
      await _secureStore.delete(SecureStoreKey.deviceId);
    }
    final deviceId = _uuid.v5(
      Namespace.url.value,
      '$masterSecret:${instanceScope.storageId}',
    );

    final platform = Platform.operatingSystem;
    return DeviceIdentity(
      id: deviceId,
      platform: platform,
      displayName: 'Ứng dụng chat ${_titleCase(platform)}',
    );
  }
}

String _titleCase(String value) {
  if (value.isEmpty) {
    return value;
  }
  return value[0].toUpperCase() + value.substring(1);
}

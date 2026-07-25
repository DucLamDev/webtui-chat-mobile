import 'dart:io';

import 'package:uuid/uuid.dart';

import '../../../../core/security/secure_key_value_store.dart';
import '../../domain/entities/device_identity.dart';
import '../../domain/repositories/device_identity_repository.dart';

final class SecureDeviceIdentityRepository implements DeviceIdentityRepository {
  const SecureDeviceIdentityRepository({
    required SecureKeyValueStore secureStore,
    Uuid uuid = const Uuid(),
  }) : _secureStore = secureStore,
       _uuid = uuid;

  final SecureKeyValueStore _secureStore;
  final Uuid _uuid;

  @override
  Future<DeviceIdentity> currentDevice() async {
    var deviceId = await _secureStore.read(SecureStoreKey.deviceId);
    if (deviceId == null || deviceId.trim().isEmpty) {
      deviceId = _uuid.v4();
      await _secureStore.write(SecureStoreKey.deviceId, deviceId);
    }

    final platform = Platform.operatingSystem;
    return DeviceIdentity(
      id: deviceId,
      platform: platform,
      displayName: 'WebTui ${_titleCase(platform)}',
    );
  }
}

String _titleCase(String value) {
  if (value.isEmpty) {
    return value;
  }
  return value[0].toUpperCase() + value.substring(1);
}

import '../entities/device_identity.dart';

abstract interface class DeviceIdentityRepository {
  Future<DeviceIdentity> currentDevice();
}

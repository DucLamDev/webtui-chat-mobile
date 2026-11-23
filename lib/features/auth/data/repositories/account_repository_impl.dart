import 'package:dio/dio.dart';

import '../../../../core/network/api_transport.dart';
import '../../../../core/result/result.dart';
import '../../../../core/result/result_guard.dart';
import '../../domain/repositories/account_repository.dart';
import '../../domain/repositories/device_identity_repository.dart';

final class AccountRepositoryImpl implements AccountRepository {
  const AccountRepositoryImpl(this._api, this._devices);

  final ApiTransport _api;
  final DeviceIdentityRepository _devices;

  @override
  Future<Result<void>> deleteAccount({
    required String confirmation,
    required String reauthToken,
    String? ownershipSuccessorEmail,
  }) {
    return guardResult(() async {
      final normalizedSuccessorEmail = ownershipSuccessorEmail?.trim();
      final device = await _devices.currentDevice();
      await _api.delete<Object>(
        '/api/v1/users/me',
        data: {
          'confirmation': confirmation,
          if (normalizedSuccessorEmail != null &&
              normalizedSuccessorEmail.isNotEmpty)
            'ownership_successor_email': normalizedSuccessorEmail,
        },
        // Xoá tài khoản bắt buộc xác thực lại trên đúng thiết bị này.
        options: Options(
          headers: {'X-Reauth-Token': reauthToken, 'X-Device-ID': device.id},
        ),
      );
    });
  }
}

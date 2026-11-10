import 'package:dio/dio.dart';
import '../../../core/network/api_response.dart';
import '../../../core/network/api_transport.dart';
import '../../../core/result/result.dart';
import '../../../core/result/result_guard.dart';
import '../../auth/domain/repositories/device_identity_repository.dart';
import '../domain/mfa_repository.dart';

final class MfaRepositoryImpl implements MfaRepository {
  const MfaRepositoryImpl(this._api, this._devices);
  final ApiTransport _api;
  final DeviceIdentityRepository _devices;
  Future<Options> _headers([String? token]) async => Options(
    headers: {
      'X-Device-ID': (await _devices.currentDevice()).id,
      'X-Reauth-Token': ?token,
    },
  );
  @override
  Future<Result<MfaStatus>> status() => guardResult(() async {
    final r = await _api.get<Object>('/api/v1/auth/mfa');
    final data = envelopeItem(r.data, 'status');
    return MfaStatus(
      enabled: data['feature_enabled'] == true,
      totpEnabled: data['totp_enabled'] == true,
    );
  });
  @override
  Future<Result<String>> reauthenticate({
    required String method,
    required String value,
  }) => guardResult(() async {
    final r = await _api.post<Object>(
      '/api/v1/auth/reauth',
      data: {
        'method': method,
        method == 'password' ? 'password' : 'code': value,
      },
      options: await _headers(),
    );
    final token = stringField(envelopeItem(r.data, 'reauth'), ['reauth_token']);
    if (token.isEmpty) {
      throw const FormatException('Máy chủ không trả mã xác thực lại.');
    }
    return token;
  });
  @override
  Future<Result<TotpEnrollment>> enroll(String token) => guardResult(() async {
    final r = await _api.post<Object>(
      '/api/v1/auth/mfa/totp/enroll',
      options: await _headers(token),
    );
    final data = envelopeItem(r.data, 'enrollment');
    return TotpEnrollment(
      secret: stringField(data, ['secret']),
      uri: stringField(data, ['otpauth_url']),
    );
  });
  @override
  Future<Result<List<String>>> confirm(String code) => guardResult(() async {
    final r = await _api.post<Object>(
      '/api/v1/auth/mfa/totp/confirm',
      data: {'code': code},
    );
    final data = envelopeItem(r.data, 'result');
    return (data['recovery_codes'] as List? ?? []).whereType<String>().toList();
  });
  @override
  Future<Result<void>> disable(String token) => guardResult(() async {
    await _api.post<Object>(
      '/api/v1/auth/mfa/totp/disable',
      options: await _headers(token),
    );
  });
}

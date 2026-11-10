import '../../../../core/network/api_response.dart';
import '../../../../core/network/api_transport.dart';
import '../../domain/entities/auth_session.dart';
import '../../domain/entities/device_identity.dart';
import '../../domain/entities/email_verification.dart';
import 'auth_remote_data_source.dart';

/// `POST /api/v1/auth/email/verify|resend` (không cần đăng nhập).
final class EmailVerificationRemoteDataSource {
  const EmailVerificationRemoteDataSource(this._api);

  final ApiTransport _api;

  Future<AuthSession> verify({
    required String verificationId,
    required String code,
    required DeviceIdentity device,
  }) async {
    final response = await _api.post<Object>(
      '/api/v1/auth/email/verify',
      data: {
        'verification_id': verificationId,
        'code': code,
        'device_name': device.displayName,
      },
    );
    return authSessionFromEnvelope(response.data);
  }

  Future<EmailVerificationTicket> resend(String verificationId) async {
    final response = await _api.post<Object>(
      '/api/v1/auth/email/resend',
      data: {'verification_id': verificationId},
    );
    final map = envelopeItem(response.data, 'verification');
    final ticket = EmailVerificationTicket.fromJson({
      'verification_id': verificationId,
      ...map,
    });
    if (ticket == null) {
      throw const FormatException('Verification payload is invalid.');
    }
    return ticket;
  }
}

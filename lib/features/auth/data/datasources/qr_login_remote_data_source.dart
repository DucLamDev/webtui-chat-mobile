import '../../../../core/network/api_response.dart';
import '../../../../core/network/api_transport.dart';
import '../../domain/entities/qr_login.dart';

/// `POST /api/v1/auth/qr/challenges/{id}/scan|approve|reject` (cần đăng nhập).
final class QrLoginRemoteDataSource {
  const QrLoginRemoteDataSource(this._api);

  final ApiTransport _api;

  Future<QrLoginScan> scan(QrLoginPayload payload) async {
    final response = await _api.post<Object>(
      _path(payload, 'scan'),
      data: {'secret': payload.secret},
    );
    final map = envelopeItem(response.data, 'challenge');
    final requester = jsonMap(field(map, const ['requester']));
    return QrLoginScan(
      challengeId: stringField(map, const [
        'challenge_id',
      ], fallback: payload.challengeId),
      status: stringField(map, const ['status'], fallback: 'scanned'),
      expiresAt: nullableDateTimeField(map, const ['expires_at']),
      requester: QrLoginRequester(
        deviceName: nullableStringField(requester, const ['device_name']),
        userAgent: nullableStringField(requester, const ['user_agent']),
        ipAddress: nullableStringField(requester, const ['ip_address']),
        createdAt: nullableDateTimeField(requester, const ['created_at']),
      ),
    );
  }

  Future<String> approve(QrLoginPayload payload) {
    return _decide(payload, 'approve', fallbackStatus: 'approved');
  }

  Future<String> reject(QrLoginPayload payload) {
    return _decide(payload, 'reject', fallbackStatus: 'rejected');
  }

  Future<String> _decide(
    QrLoginPayload payload,
    String action, {
    required String fallbackStatus,
  }) async {
    final response = await _api.post<Object>(
      _path(payload, action),
      data: {'secret': payload.secret},
    );
    final map = envelopeItem(response.data, 'challenge');
    return stringField(map, const ['status'], fallback: fallbackStatus);
  }
}

/// `challengeId` đã được [QrLoginPayload.tryParse] giới hạn trong
/// `[A-Za-z0-9_-]`; vẫn mã hoá thành một đoạn đường dẫn cho chắc.
String _path(QrLoginPayload payload, String action) {
  final id = Uri.encodeComponent(payload.challengeId);
  return '/api/v1/auth/qr/challenges/$id/$action';
}

import 'package:dio/dio.dart';

import '../../../core/error/error_mapper.dart';
import '../../../core/error/failure.dart';
import '../../../core/network/api_response.dart';
import '../../../core/network/api_transport.dart';
import '../domain/ide_server_access.dart';

enum IdePairRemoteStatus { pending, ok, rejected, expired, invalid }

final class IdePairPoll {
  const IdePairPoll(this.status, {this.deviceId, this.pushLinked});

  final IdePairRemoteStatus status;
  final String? deviceId;

  /// Chỉ có khi `ok`: máy IDE đã nối với thiết bị chat để đẩy thông báo.
  /// `null` = máy chủ cũ không báo.
  final bool? pushLinked;
}

enum IdePairErrorKind {
  offline,
  rateLimited,
  busy,
  invalid,

  /// HTTP 403 `IDE_ACCESS_DENIED`: máy chủ chat không cho tài khoản dùng IDE.
  accessDenied,
  other,
}

final class IdePairException implements Exception {
  const IdePairException(this.kind, [this.failure, this.notFound = false]);

  /// HTTP 404.
  final bool notFound;

  final IdePairErrorKind kind;
  final Failure? failure;

  /// `details.reason` khi [kind] là `accessDenied` (`unavailable` nếu thiếu).
  String get accessReason {
    final reason = failure?.details['reason'];
    return reason is String && reason.trim().isNotEmpty
        ? reason.trim()
        : 'unavailable';
  }

  @override
  String toString() => 'IdePairException($kind)';
}

/// Ba API gắn máy của máy chủ chat (hợp đồng mục 6).
final class IdePairApi {
  const IdePairApi(this._api);

  final ApiTransport _api;

  static const _base = '/api/v1/ide';

  Future<String> requestPair({
    required String code,
    required String pubkey,
    required String stepPubkey,
    required String deviceName,
    String? chatDeviceId,
  }) async {
    final response = await _guard(
      () => _api.post<Object>(
        '$_base/pair',
        data: {
          'code': code,
          'pubkey': pubkey,
          'step_pubkey': stepPubkey,
          'device_name': deviceName,
          if (chatDeviceId != null && chatDeviceId.isNotEmpty)
            'chat_device_id': chatDeviceId,
        },
      ),
    );
    final id = jsonMap(envelopeData(response.data))['pair_request_id'];
    if (id is! String || id.isEmpty) {
      throw const IdePairException(IdePairErrorKind.other);
    }
    return id;
  }

  Future<IdePairPoll> poll(String pairRequestId) async {
    final Response<Object> response;
    try {
      response = await _guard(
        () => _api.get<Object>(
          '$_base/pair/${Uri.encodeComponent(pairRequestId)}',
        ),
      );
    } on IdePairException catch (error) {
      // Mã lạ: máy chủ trả 404, coi như `invalid`.
      if (error.failure?.hasCode('NOT_FOUND') == true || error.notFound) {
        return const IdePairPoll(IdePairRemoteStatus.invalid);
      }
      rethrow;
    }
    final data = jsonMap(envelopeData(response.data));
    final status = switch (data['status']) {
      'ok' => IdePairRemoteStatus.ok,
      'rejected' => IdePairRemoteStatus.rejected,
      'expired' => IdePairRemoteStatus.expired,
      'invalid' => IdePairRemoteStatus.invalid,
      _ => IdePairRemoteStatus.pending,
    };
    final device = data['device_id'];
    final push = data['push_linked'];
    return IdePairPoll(
      status,
      deviceId: device is String ? device : null,
      pushLinked: push is bool ? push : null,
    );
  }

  /// `DELETE /ide/pair/devices/{id}`: gỡ máy IDE của chính người dùng khỏi máy
  /// chủ. Lỗi mạng / 404 / lỗi khác đều bỏ qua (không chặn việc gỡ ở máy).
  Future<void> removeDevice(String ideDeviceId) async {
    try {
      await _api.delete<Object>(
        '$_base/pair/devices/${Uri.encodeComponent(ideDeviceId)}',
      );
    } on Object {
      return;
    }
  }

  /// `GET /ide/status`: IDE đang nối vào máy chủ chat hay không, và (máy chủ
  /// mới) IDE có bật / tài khoản có được dùng không.
  Future<IdeServerStatus> status() async {
    final Response<Object> response;
    try {
      response = await _guard(() => _api.get<Object>('$_base/status'));
    } on IdePairException catch (error) {
      // Máy chủ từ chối IDE ngay ở trạng thái (403 / 503 IDE_ACCESS_DENIED).
      if (error.kind != IdePairErrorKind.accessDenied) rethrow;
      return IdeServerStatus(
        connected: false,
        access: IdeServerAccess(allowed: false, reason: error.accessReason),
      );
    }
    return IdeServerStatus.fromJson(jsonMap(envelopeData(response.data)));
  }

  Future<Response<T>> _guard<T>(Future<Response<T>> Function() call) async {
    try {
      return await call();
    } on DioException catch (error) {
      final failure = mapDioExceptionToFailure(error);
      final status = error.response?.statusCode ?? 0;
      // 403 (không đủ điều kiện) hoặc 503 (chưa kiểm được) kèm details.reason.
      final kind = failure.hasCode(ideAccessDeniedCode)
          ? IdePairErrorKind.accessDenied
          : failure.hasCode('RATE_LIMIT_UNAVAILABLE')
          ? IdePairErrorKind.busy
          : failure.hasCode('IDE_OFFLINE') || status == 503
          ? IdePairErrorKind.offline
          : status == 429
          ? IdePairErrorKind.rateLimited
          : status == 400 || status == 422
          ? IdePairErrorKind.invalid
          : IdePairErrorKind.other;
      throw IdePairException(kind, failure, status == 404);
    }
  }
}

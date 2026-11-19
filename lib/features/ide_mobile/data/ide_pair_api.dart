import 'package:dio/dio.dart';

import '../../../core/error/error_mapper.dart';
import '../../../core/error/failure.dart';
import '../../../core/network/api_response.dart';
import '../../../core/network/api_transport.dart';

enum IdePairRemoteStatus { pending, ok, rejected, expired, invalid }

final class IdePairPoll {
  const IdePairPoll(this.status, {this.deviceId});

  final IdePairRemoteStatus status;
  final String? deviceId;
}

enum IdePairErrorKind { offline, rateLimited, invalid, other }

final class IdePairException implements Exception {
  const IdePairException(this.kind, [this.failure, this.notFound = false]);

  /// HTTP 404.
  final bool notFound;

  final IdePairErrorKind kind;
  final Failure? failure;

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
  }) async {
    final response = await _guard(
      () => _api.post<Object>(
        '$_base/pair',
        data: {
          'code': code,
          'pubkey': pubkey,
          'step_pubkey': stepPubkey,
          'device_name': deviceName,
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
    return IdePairPoll(status, deviceId: device is String ? device : null);
  }

  /// `GET /ide/status`: IDE đang nối vào máy chủ chat hay không.
  Future<bool> isConnected() async {
    final response = await _guard(() => _api.get<Object>('$_base/status'));
    return jsonMap(envelopeData(response.data))['connected'] == true;
  }

  Future<Response<T>> _guard<T>(Future<Response<T>> Function() call) async {
    try {
      return await call();
    } on DioException catch (error) {
      final failure = mapDioExceptionToFailure(error);
      final status = error.response?.statusCode ?? 0;
      final kind = failure.hasCode('IDE_OFFLINE') || status == 503
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

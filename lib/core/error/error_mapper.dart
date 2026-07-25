import 'package:dio/dio.dart';

import 'failure.dart';

Failure mapDioExceptionToFailure(DioException exception) {
  final requestId = _requestIdFrom(exception);
  final host = exception.requestOptions.uri.host;
  final serverLabel = host.isEmpty ? 'máy chủ' : host;

  return switch (exception.type) {
    DioExceptionType.connectionTimeout ||
    DioExceptionType.sendTimeout ||
    DioExceptionType.transformTimeout ||
    DioExceptionType.receiveTimeout => Failure(
      kind: FailureKind.timeout,
      message: 'Kết nối quá hạn. Vui lòng thử lại.',
      requestId: requestId,
      cause: exception,
    ),
    DioExceptionType.cancel => Failure(
      kind: FailureKind.cancelled,
      message: 'Yêu cầu đã bị hủy.',
      requestId: requestId,
      cause: exception,
    ),
    DioExceptionType.badResponse => _failureFromResponse(
      exception.response,
      requestId,
      exception,
    ),
    DioExceptionType.connectionError => Failure(
      kind: FailureKind.network,
      message:
          'Không thể kết nối $serverLabel. Kiểm tra Internet hoặc trạng thái máy chủ.',
      requestId: requestId,
      cause: exception,
    ),
    DioExceptionType.badCertificate => Failure(
      kind: FailureKind.network,
      message: 'Chứng chỉ HTTPS của $serverLabel không hợp lệ.',
      requestId: requestId,
      cause: exception,
    ),
    DioExceptionType.unknown => Failure(
      kind: FailureKind.unknown,
      message: 'Đã có lỗi không xác định.',
      requestId: requestId,
      cause: exception,
    ),
  };
}

Failure _failureFromResponse(
  Response<dynamic>? response,
  String? requestId,
  Object cause,
) {
  final statusCode = response?.statusCode ?? 0;
  final envelope = _ErrorEnvelope.tryParse(response?.data);

  return Failure(
    kind: _kindFromStatus(statusCode),
    message: envelope?.message ?? _messageFromStatus(statusCode),
    code: envelope?.code,
    requestId: envelope?.requestId ?? requestId,
    cause: cause,
  );
}

FailureKind _kindFromStatus(int statusCode) {
  return switch (statusCode) {
    400 => FailureKind.validation,
    401 => FailureKind.unauthorized,
    403 => FailureKind.forbidden,
    404 => FailureKind.notFound,
    409 => FailureKind.conflict,
    422 => FailureKind.validation,
    429 => FailureKind.rateLimited,
    >= 500 => FailureKind.server,
    _ => FailureKind.unknown,
  };
}

String _messageFromStatus(int statusCode) {
  return switch (statusCode) {
    401 => 'Phiên đăng nhập đã hết hạn.',
    403 => 'Bạn không có quyền thực hiện thao tác này.',
    404 => 'Không tìm thấy dữ liệu.',
    409 => 'Dữ liệu đã thay đổi, vui lòng tải lại.',
    422 || 400 => 'Dữ liệu không hợp lệ.',
    429 => 'Thao tác quá nhanh, vui lòng thử lại sau.',
    >= 500 => 'Máy chủ đang gặp lỗi.',
    _ => 'Yêu cầu không thành công.',
  };
}

String? _requestIdFrom(DioException exception) {
  return exception.response?.headers.value('x-request-id') ??
      exception.response?.headers.value('X-Request-ID') ??
      exception.requestOptions.headers['X-Request-ID']?.toString();
}

final class _ErrorEnvelope {
  const _ErrorEnvelope({this.code, this.message, this.requestId});

  final String? code;
  final String? message;
  final String? requestId;

  static _ErrorEnvelope? tryParse(Object? data) {
    if (data is! Map) {
      return null;
    }

    final error = data['error'];
    final errorMap = error is Map ? error : const {};

    return _ErrorEnvelope(
      code: (errorMap['code'] ?? data['code'])?.toString(),
      message: (errorMap['message'] ?? data['message'])?.toString(),
      requestId: (data['request_id'] ?? data['requestId'])?.toString(),
    );
  }
}

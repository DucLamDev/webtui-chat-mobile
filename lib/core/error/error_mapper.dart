import 'package:dio/dio.dart';

import '../../l10n/app_strings.dart';
import 'failure.dart';

String get _genericErrorMessage => tr(
  'Chưa thực hiện được. Vui lòng thử lại.',
  'Could not complete that. Please try again.',
);

/// Câu báo lỗi hiện cho người dùng: không lộ chữ kỹ thuật tiếng Anh
/// (`DioException [bad response]...`, `Bad state: ...`). Lỗi nội bộ không có
/// câu tiếng Việt thì dùng câu chung.
String userFacingErrorMessage(Object error) {
  final message = switch (error) {
    DioException() => mapDioExceptionToFailure(error).message,
    Failure(:final message) => message,
    StateError(:final message) => message,
    _ => error.toString().replaceFirst(RegExp(r'^Exception:\s*'), ''),
  };
  final trimmed = message.trim();
  // Tiếng Việt: chỉ giữ câu có ký tự ngoài ASCII (câu viết cho người dùng).
  // Tiếng Anh: câu của app cũng là ASCII nên tin các lỗi do app tạo ra.
  final appMessage =
      AppStrings.current.isEnglish &&
      (error is DioException || error is Failure || error is StateError);
  if (trimmed.isEmpty ||
      (!appMessage && !trimmed.runes.any((rune) => rune > 0x7f))) {
    return _genericErrorMessage;
  }
  return trimmed;
}

Failure mapDioExceptionToFailure(DioException exception) {
  final requestId = _requestIdFrom(exception);
  final host = exception.requestOptions.uri.host;
  final serverLabel = host.isEmpty ? tr('máy chủ', 'server') : host;

  return switch (exception.type) {
    DioExceptionType.connectionTimeout ||
    DioExceptionType.sendTimeout ||
    DioExceptionType.transformTimeout ||
    DioExceptionType.receiveTimeout => Failure(
      kind: FailureKind.timeout,
      message: tr(
        'Kết nối quá hạn. Vui lòng thử lại.',
        'Connection timed out. Please try again.',
      ),
      requestId: requestId,
      cause: exception,
    ),
    DioExceptionType.cancel => Failure(
      kind: FailureKind.cancelled,
      message: tr('Yêu cầu đã bị hủy.', 'Request canceled.'),
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
      message: tr(
        'Không thể kết nối $serverLabel. Kiểm tra Internet hoặc trạng thái máy chủ.',
        'Could not connect to $serverLabel. Check your internet or the server status.',
      ),
      requestId: requestId,
      cause: exception,
    ),
    DioExceptionType.badCertificate => Failure(
      kind: FailureKind.network,
      message: tr(
        'Chứng chỉ HTTPS của $serverLabel không hợp lệ.',
        'The HTTPS certificate of $serverLabel is not valid.',
      ),
      requestId: requestId,
      cause: exception,
    ),
    DioExceptionType.unknown => Failure(
      kind: FailureKind.unknown,
      message: tr('Đã có lỗi không xác định.', 'An unknown error occurred.'),
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
    details: envelope?.details ?? const {},
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
    401 => tr('Phiên đăng nhập đã hết hạn.', 'Your session has expired.'),
    403 => tr(
      'Bạn không có quyền thực hiện thao tác này.',
      'You do not have permission to do this.',
    ),
    404 => tr('Không tìm thấy dữ liệu.', 'Data not found.'),
    409 => tr(
      'Dữ liệu đã thay đổi, vui lòng tải lại.',
      'The data has changed. Please reload.',
    ),
    422 || 400 => tr('Dữ liệu không hợp lệ.', 'Invalid data.'),
    429 => tr(
      'Yêu cầu tạm thời chưa thể xử lý. Vui lòng thử lại sau ít phút.',
      'The request cannot be processed right now. Please try again in a few minutes.',
    ),
    >= 500 => tr('Máy chủ đang gặp lỗi.', 'The server is having problems.'),
    _ => tr('Yêu cầu không thành công.', 'The request failed.'),
  };
}

String? _requestIdFrom(DioException exception) {
  return exception.response?.headers.value('x-request-id') ??
      exception.response?.headers.value('X-Request-ID') ??
      exception.requestOptions.headers['X-Request-ID']?.toString();
}

final class _ErrorEnvelope {
  const _ErrorEnvelope({
    this.code,
    this.message,
    this.requestId,
    this.details = const {},
  });

  final String? code;
  final String? message;
  final String? requestId;
  final Map<String, Object?> details;

  static _ErrorEnvelope? tryParse(Object? data) {
    if (data is! Map) {
      return null;
    }

    final error = data['error'];
    final errorMap = error is Map ? error : const {};
    final details = errorMap['details'];

    return _ErrorEnvelope(
      code: (errorMap['code'] ?? data['code'])?.toString(),
      message: (errorMap['message'] ?? data['message'])?.toString(),
      requestId: (data['request_id'] ?? data['requestId'])?.toString(),
      details: details is Map
          ? Map<String, Object?>.unmodifiable({
              for (final entry in details.entries)
                entry.key.toString(): entry.value,
            })
          : const {},
    );
  }
}

enum FailureKind {
  network,
  timeout,
  cancelled,
  unauthorized,
  forbidden,
  notFound,
  validation,
  conflict,
  rateLimited,
  server,
  decoding,
  storage,
  unknown,
}

final class Failure {
  const Failure({
    required this.kind,
    required this.message,
    this.code,
    this.requestId,
    this.cause,
    this.details = const {},
  });

  final FailureKind kind;
  final String message;
  final String? code;
  final String? requestId;
  final Object? cause;

  /// `error.details` của envelope máy chủ (vd. `attempts_left`,
  /// `verification_id`, `retry_after_seconds`, `reason`). Rỗng khi không có.
  final Map<String, Object?> details;

  bool get requiresLogin => kind == FailureKind.unauthorized;

  /// So mã lỗi máy chủ (`error.code`), không phân biệt hoa thường / khoảng trắng.
  bool hasCode(String value) =>
      code?.trim().toUpperCase() == value.trim().toUpperCase();

  Failure copyWith({
    FailureKind? kind,
    String? message,
    String? code,
    String? requestId,
    Object? cause,
    Map<String, Object?>? details,
  }) {
    return Failure(
      kind: kind ?? this.kind,
      message: message ?? this.message,
      code: code ?? this.code,
      requestId: requestId ?? this.requestId,
      cause: cause ?? this.cause,
      details: details ?? this.details,
    );
  }
}

/// Lỗi nghiệp vụ đã rõ, ném từ data layer để `guardResult` trả nguyên
/// [failure] thay vì gộp thành lỗi giải mã dữ liệu.
final class FailureException implements Exception {
  const FailureException(this.failure);

  final Failure failure;

  @override
  String toString() => 'FailureException(${failure.code})';
}

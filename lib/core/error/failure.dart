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
  });

  final FailureKind kind;
  final String message;
  final String? code;
  final String? requestId;
  final Object? cause;

  bool get requiresLogin => kind == FailureKind.unauthorized;

  Failure copyWith({
    FailureKind? kind,
    String? message,
    String? code,
    String? requestId,
    Object? cause,
  }) {
    return Failure(
      kind: kind ?? this.kind,
      message: message ?? this.message,
      code: code ?? this.code,
      requestId: requestId ?? this.requestId,
      cause: cause ?? this.cause,
    );
  }
}

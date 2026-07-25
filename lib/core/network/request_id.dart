import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

abstract interface class RequestIdGenerator {
  String next();
}

final class UuidRequestIdGenerator implements RequestIdGenerator {
  const UuidRequestIdGenerator({Uuid uuid = const Uuid()}) : _uuid = uuid;

  final Uuid _uuid;

  @override
  String next() => _uuid.v4();
}

final class RequestIdInterceptor extends Interceptor {
  RequestIdInterceptor(this._requestIds);

  final RequestIdGenerator _requestIds;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.headers.putIfAbsent('X-Request-ID', _requestIds.next);
    handler.next(options);
  }
}

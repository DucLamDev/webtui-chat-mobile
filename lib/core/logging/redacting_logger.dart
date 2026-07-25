import 'dart:developer' as developer;

import 'package:dio/dio.dart';

typedef LogSink = void Function(String message);

final class RedactingLogger {
  RedactingLogger({LogSink? sink}) : _sink = sink ?? _defaultSink;

  final LogSink _sink;

  void debug(String message, [Map<String, Object?> context = const {}]) {
    _sink(_format('DEBUG', message, context));
  }

  void info(String message, [Map<String, Object?> context = const {}]) {
    _sink(_format('INFO', message, context));
  }

  void warning(String message, [Map<String, Object?> context = const {}]) {
    _sink(_format('WARN', message, context));
  }

  String redact(String input) {
    var output = input;
    for (final pattern in _sensitiveAssignments) {
      output = output.replaceAllMapped(pattern, (match) {
        return '${match.group(1)}<redacted>';
      });
    }
    return output;
  }

  String _format(String level, String message, Map<String, Object?> context) {
    final normalizedContext = context.entries
        .map((entry) => '${entry.key}=${redact('${entry.value}')}')
        .join(' ');

    final suffix = normalizedContext.isEmpty ? '' : ' $normalizedContext';
    return redact('[$level] $message$suffix');
  }

  static void _defaultSink(String message) {
    developer.log(message, name: 'webtui.mobile');
  }

  static final List<RegExp> _sensitiveAssignments = [
    RegExp(
      r'((authorization)\s*[:=]\s*)(bearer\s+)?([^,\s}&]+)',
      caseSensitive: false,
    ),
    RegExp(
      r'((cookie|set-cookie|refresh_token|access_token|token|password|secret|api_key)\s*[:=]\s*)([^,\s}&]+)',
      caseSensitive: false,
    ),
    RegExp(
      r'(([?&](access_token|refresh_token|token|password|secret|api_key)=))([^&\s]+)',
      caseSensitive: false,
    ),
  ];
}

final class RedactingDioLogInterceptor extends Interceptor {
  RedactingDioLogInterceptor(this._logger);

  final RedactingLogger _logger;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    _logger.debug('Bắt đầu yêu cầu HTTP', {
      'method': options.method,
      'path': options.uri.path,
      'request_id': options.headers['X-Request-ID'],
    });
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    _logger.debug('Hoàn tất yêu cầu HTTP', {
      'status': response.statusCode,
      'path': response.requestOptions.uri.path,
      'request_id': response.requestOptions.headers['X-Request-ID'],
    });
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _logger.warning('Yêu cầu HTTP thất bại', {
      'type': err.type.name,
      'path': err.requestOptions.uri.path,
      'status': err.response?.statusCode,
      'request_id': err.requestOptions.headers['X-Request-ID'],
    });
    handler.next(err);
  }
}

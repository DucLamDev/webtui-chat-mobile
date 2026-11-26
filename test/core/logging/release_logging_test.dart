import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/logging/redacting_logger.dart';

void main() {
  test('bản phát hành không ghi nhật ký ở mọi mức', () {
    final logs = <String>[];
    final logger = RedactingLogger(sink: logs.add, release: true)
      ..debug('d')
      ..info('i')
      ..warning('w');
    expect(logger, isNotNull);
    expect(logs, isEmpty);

    final dev = RedactingLogger(sink: logs.add, release: false)..debug('d');
    expect(dev, isNotNull);
    expect(logs, hasLength(1));
  });

  test('bản phát hành tắt debugPrint', () {
    final original = debugPrint;
    addTearDown(() => debugPrint = original);
    final printed = <String?>[];
    debugPrint = (message, {wrapWidth}) => printed.add(message);

    silenceDebugLogsInRelease(release: false);
    debugPrint('bản thử');
    expect(printed, ['bản thử']);

    silenceDebugLogsInRelease(release: true);
    debugPrint('bản phát hành');
    expect(printed, ['bản thử']);
  });

  test('nhật ký HTTP không ghi nội dung gửi / nhận (vd nội dung IDE)', () {
    final logs = <String>[];
    final interceptor = RedactingDioLogInterceptor(
      RedactingLogger(sink: logs.add, release: false),
    );
    final options = RequestOptions(
      path: '/api/v1/ide/pair',
      method: 'POST',
      data: {'code': 'MA-GAN-BI-MAT', 'device_name': 'noi-dung-ide'},
      headers: {'Authorization': 'Bearer tok-bi-mat'},
    );
    interceptor.onRequest(options, RequestInterceptorHandler());
    interceptor.onResponse(
      Response(
        requestOptions: options,
        statusCode: 200,
        data: {'secret_file': 'noi-dung-tep-ide'},
      ),
      ResponseInterceptorHandler(),
    );
    final all = logs.join('\n');
    expect(logs, hasLength(2));
    for (final leaked in [
      'MA-GAN-BI-MAT',
      'noi-dung-ide',
      'tok-bi-mat',
      'noi-dung-tep-ide',
    ]) {
      expect(all, isNot(contains(leaked)));
    }
  });
}

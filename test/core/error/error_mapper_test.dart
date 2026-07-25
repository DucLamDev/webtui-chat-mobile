import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/error/error_mapper.dart';
import 'package:webtui_chat/core/error/failure.dart';

void main() {
  test('maps 403 envelope to forbidden failure with request id', () {
    final exception = DioException(
      requestOptions: RequestOptions(path: '/secure'),
      response: Response<Map<String, Object?>>(
        requestOptions: RequestOptions(path: '/secure'),
        statusCode: 403,
        data: const {
          'request_id': 'req-1',
          'error': {
            'code': 'permission_denied',
            'message': 'Bạn không có quyền.',
          },
        },
      ),
      type: DioExceptionType.badResponse,
    );

    final failure = mapDioExceptionToFailure(exception);

    expect(failure.kind, FailureKind.forbidden);
    expect(failure.code, 'permission_denied');
    expect(failure.requestId, 'req-1');
    expect(failure.message, 'Bạn không có quyền.');
  });
}

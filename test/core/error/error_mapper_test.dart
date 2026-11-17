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

  test('maps a bare 429 without blaming normal user interaction', () {
    final options = RequestOptions(path: '/auth/login');
    final exception = DioException(
      requestOptions: options,
      response: Response<Object?>(requestOptions: options, statusCode: 429),
      type: DioExceptionType.badResponse,
    );

    final failure = mapDioExceptionToFailure(exception);

    expect(failure.kind, FailureKind.rateLimited);
    expect(
      failure.message,
      'Yêu cầu tạm thời chưa thể xử lý. Vui lòng thử lại sau ít phút.',
    );
    expect(failure.message, isNot(contains('thao tác quá nhanh')));
  });

  test('user-facing message hides technical English errors', () {
    final options = RequestOptions(path: '/tasks');
    final dio = DioException(
      requestOptions: options,
      response: Response<Object?>(
        requestOptions: options,
        statusCode: 422,
        data: const {
          'error': {'message': 'Tiêu đề task không được trống.'},
        },
      ),
      type: DioExceptionType.badResponse,
    );

    expect(userFacingErrorMessage(dio), 'Tiêu đề task không được trống.');
    expect(
      userFacingErrorMessage(StateError('Cuộc gọi không còn khả dụng.')),
      'Cuộc gọi không còn khả dụng.',
    );
    expect(
      userFacingErrorMessage(Exception('Không lưu được ghi chú.')),
      'Không lưu được ghi chú.',
    );
    for (final error in [
      StateError('instance binding changed'),
      const FormatException('Unexpected character'),
      Exception(),
    ]) {
      expect(
        userFacingErrorMessage(error),
        'Chưa thực hiện được. Vui lòng thử lại.',
      );
    }
  });

  group('failureKindOf', () {
    DioException badResponse(int status) {
      final options = RequestOptions(path: '/users/u-2/profile');
      return DioException(
        requestOptions: options,
        response: Response<Object?>(
          requestOptions: options,
          statusCode: status,
        ),
        type: DioExceptionType.badResponse,
      );
    }

    test('lỗi Dio theo mã HTTP: 404 không tìm thấy, 403 không có quyền', () {
      expect(failureKindOf(badResponse(404)), FailureKind.notFound);
      expect(failureKindOf(badResponse(403)), FailureKind.forbidden);
      expect(failureKindOf(badResponse(500)), FailureKind.server);
    });

    test('có mã HTTP mà Dio không gắn loại badResponse vẫn theo mã', () {
      final options = RequestOptions(path: '/users/u-2/profile');
      final exception = DioException(
        requestOptions: options,
        response: Response<Object?>(requestOptions: options, statusCode: 404),
      );
      expect(failureKindOf(exception), FailureKind.notFound);
    });

    test('mất mạng không bị coi là không tìm thấy', () {
      final exception = DioException(
        requestOptions: RequestOptions(path: '/users/u-2/profile'),
        type: DioExceptionType.connectionError,
      );
      expect(failureKindOf(exception), FailureKind.network);
    });

    test('Failure / FailureException giữ nguyên loại; lỗi khác là unknown', () {
      const failure = Failure(kind: FailureKind.notFound, message: 'x');
      expect(failureKindOf(failure), FailureKind.notFound);
      expect(
        failureKindOf(const FailureException(failure)),
        FailureKind.notFound,
      );
      expect(failureKindOf(StateError('x')), FailureKind.unknown);
      expect(failureKindOf(null), FailureKind.unknown);
    });
  });
}

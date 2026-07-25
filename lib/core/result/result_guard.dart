import 'package:dio/dio.dart';

import '../error/error_mapper.dart';
import '../error/failure.dart';
import 'result.dart';

Future<Result<T>> guardResult<T>(
  Future<T> Function() body, {
  String decodingMessage = 'Không thể xử lý dữ liệu từ máy chủ.',
}) async {
  try {
    return Success(await body());
  } on DioException catch (error) {
    return FailureResult(mapDioExceptionToFailure(error));
  } on Object catch (error) {
    return FailureResult(
      Failure(
        kind: FailureKind.decoding,
        message: decodingMessage,
        code: 'DECODING_FAILURE',
        cause: error,
      ),
    );
  }
}

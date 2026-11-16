import 'package:dio/dio.dart';

import '../../l10n/app_strings.dart';
import '../error/error_mapper.dart';
import '../error/failure.dart';
import 'result.dart';

Future<Result<T>> guardResult<T>(
  Future<T> Function() body, {
  String? decodingMessage,
}) async {
  try {
    return Success(await body());
  } on DioException catch (error) {
    return FailureResult(mapDioExceptionToFailure(error));
  } on FailureException catch (error) {
    return FailureResult(error.failure);
  } on Object catch (error) {
    return FailureResult(
      Failure(
        kind: FailureKind.decoding,
        message:
            decodingMessage ??
            tr(
              'Không thể xử lý dữ liệu từ máy chủ.',
              'Could not process data from the server.',
            ),
        code: 'DECODING_FAILURE',
        cause: error,
      ),
    );
  }
}

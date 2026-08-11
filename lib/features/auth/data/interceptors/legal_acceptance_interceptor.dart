import 'package:dio/dio.dart';

import '../../application/legal_acceptance_access_policy.dart';

final class LegalAcceptanceInterceptor extends Interceptor {
  LegalAcceptanceInterceptor(this._policy);

  final LegalAcceptanceAccessPolicy _policy;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (!_policy.shouldBlock(options)) {
      handler.next(options);
      return;
    }
    _policy.requireAcceptance();
    handler.reject(
      DioException.badResponse(
        statusCode: 409,
        requestOptions: options,
        response: Response<Object>(
          requestOptions: options,
          statusCode: 409,
          data: const {
            'success': false,
            'error': {
              'code': 'LEGAL_ACCEPTANCE_REQUIRED',
              'message':
                  'Bạn cần đồng ý Điều khoản và Chính sách quyền riêng tư trước khi tạo nội dung.',
            },
          },
        ),
      ),
    );
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (_isLegalAcceptanceRequired(err.response)) {
      _policy.requireAcceptance();
    }
    handler.next(err);
  }
}

bool _isLegalAcceptanceRequired(Response<dynamic>? response) {
  if (response?.statusCode != 409 || response?.data is! Map) {
    return false;
  }
  final body = response!.data! as Map;
  final error = body['error'];
  final errorMap = error is Map ? error : const {};
  final code = (errorMap['code'] ?? body['code'])?.toString().trim();
  return code == 'LEGAL_ACCEPTANCE_REQUIRED';
}

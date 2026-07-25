import 'package:dio/dio.dart';

import '../../../../core/result/result.dart';
import '../../application/use_cases/refresh_access_token_use_case.dart';
import '../../domain/entities/auth_session.dart';
import '../../domain/repositories/auth_token_repository.dart';

final class AuthRefreshInterceptor extends Interceptor {
  AuthRefreshInterceptor({
    required Dio dio,
    required AuthTokenRepository tokenRepository,
    required RefreshAccessTokenUseCase refreshAccessTokenUseCase,
  }) : _dio = dio,
       _tokenRepository = tokenRepository,
       _refreshAccessTokenUseCase = refreshAccessTokenUseCase;

  static const _retriedKey = 'webtui_auth_retried';

  final Dio _dio;
  final AuthTokenRepository _tokenRepository;
  final RefreshAccessTokenUseCase _refreshAccessTokenUseCase;

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = (await _tokenRepository.readAccessToken())?.trim();
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final statusCode = err.response?.statusCode;
    final request = err.requestOptions;
    if (statusCode != 401 ||
        request.extra[_retriedKey] == true ||
        request.path.contains('/api/v1/auth/refresh')) {
      handler.next(err);
      return;
    }

    final refreshResult = await _refreshAccessTokenUseCase.execute();
    if (refreshResult case Success<AuthSession>(value: final session)) {
      final token = session.tokens.accessToken.trim();
      if (token.isNotEmpty) {
        request.extra[_retriedKey] = true;
        request.headers['Authorization'] = 'Bearer $token';
        try {
          handler.resolve(await _dio.fetch<dynamic>(request));
          return;
        } on DioException catch (retryError) {
          handler.next(retryError);
          return;
        }
      }
    }

    handler.next(err);
  }
}

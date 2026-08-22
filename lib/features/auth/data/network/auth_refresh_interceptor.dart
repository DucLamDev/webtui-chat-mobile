import 'package:dio/dio.dart';

import '../../../../core/result/result.dart';
import '../../../../core/security/instance_scope.dart';
import '../../application/use_cases/refresh_access_token_use_case.dart';
import '../../domain/entities/auth_session.dart';
import '../../domain/repositories/auth_token_repository.dart';

final class AuthRefreshInterceptor extends Interceptor {
  AuthRefreshInterceptor({
    required Dio dio,
    required InstanceScope expectedInstanceScope,
    required AuthTokenRepository tokenRepository,
    required RefreshAccessTokenUseCase refreshAccessTokenUseCase,
  }) : _dio = dio,
       _expectedInstanceScope = expectedInstanceScope,
       _tokenRepository = tokenRepository,
       _refreshAccessTokenUseCase = refreshAccessTokenUseCase;

  static const _retriedKey = 'webtui_auth_retried';
  static const _mutationGuardKey = 'webtui_auth_mutation_guard';

  final Dio _dio;
  final InstanceScope _expectedInstanceScope;
  final AuthTokenRepository _tokenRepository;
  final RefreshAccessTokenUseCase _refreshAccessTokenUseCase;

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    options.headers.removeWhere(
      (key, _) => key.toLowerCase() == 'authorization',
    );
    if (!serverOriginsMatch(options.uri, _expectedInstanceScope.origin)) {
      handler.next(options);
      return;
    }
    final guard = await _tokenRepository.captureMutationGuard();
    if (guard == null ||
        guard.instanceScopeId != _expectedInstanceScope.storageId) {
      handler.next(options);
      return;
    }
    options.extra[_mutationGuardKey] = guard;
    final token = (await _tokenRepository.readAccessTokenIfCurrent(
      guard,
    ))?.trim();
    if (token != null && token.isNotEmpty) {
      options.headers = <String, dynamic>{
        ...options.headers,
        'Authorization': 'Bearer $token',
      };
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final statusCode = err.response?.statusCode;
    final request = err.requestOptions;
    if (statusCode != 401 ||
        !serverOriginsMatch(request.uri, _expectedInstanceScope.origin) ||
        request.extra[_retriedKey] == true ||
        request.path.contains('/api/v1/auth/refresh')) {
      handler.next(err);
      return;
    }

    final guard = request.extra[_mutationGuardKey];
    if (guard is! AuthTokenMutationGuard ||
        guard.instanceScopeId != _expectedInstanceScope.storageId ||
        !await _tokenRepository.isMutationGuardCurrent(guard)) {
      handler.next(err);
      return;
    }

    final refreshResult = await _refreshAccessTokenUseCase.execute(
      expectedGuard: guard,
    );
    if (refreshResult case Success<AuthSession>()) {
      if (!await _tokenRepository.isMutationGuardCurrent(guard)) {
        handler.next(err);
        return;
      }
      final token = (await _tokenRepository.readAccessTokenIfCurrent(
        guard,
      ))?.trim();
      if (token != null && token.isNotEmpty) {
        request.extra[_retriedKey] = true;
        request.headers = <String, dynamic>{
          ...request.headers,
          'Authorization': 'Bearer $token',
        };
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

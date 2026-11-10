import 'package:dio/dio.dart';

import '../../../../core/error/error_mapper.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/result/result.dart';
import '../../../../core/security/instance_scope.dart';
import '../../application/session_termination.dart';
import '../../application/use_cases/refresh_access_token_use_case.dart';
import '../../domain/entities/auth_session.dart';
import '../../domain/entities/device_approval.dart';
import '../../domain/repositories/auth_token_repository.dart';

/// Máy chủ báo phiên của request đã bị thu hồi (`401 SESSION_REVOKED`).
typedef SessionRevokedHandler =
    Future<void> Function(Failure failure, AuthTokenMutationGuard guard);

final class AuthRefreshInterceptor extends Interceptor {
  AuthRefreshInterceptor({
    required Dio dio,
    required InstanceScope expectedInstanceScope,
    required AuthTokenRepository tokenRepository,
    required RefreshAccessTokenUseCase refreshAccessTokenUseCase,
    SessionRevokedHandler? onSessionRevoked,
    void Function()? onDeviceApprovalPending,
  }) : _dio = dio,
       _expectedInstanceScope = expectedInstanceScope,
       _tokenRepository = tokenRepository,
       _refreshAccessTokenUseCase = refreshAccessTokenUseCase,
       _onSessionRevoked = onSessionRevoked,
       _onDeviceApprovalPending = onDeviceApprovalPending;

  static const _retriedKey = 'webtui_auth_retried';
  static const _mutationGuardKey = 'webtui_auth_mutation_guard';

  final Dio _dio;
  final InstanceScope _expectedInstanceScope;
  final AuthTokenRepository _tokenRepository;
  final RefreshAccessTokenUseCase _refreshAccessTokenUseCase;
  final SessionRevokedHandler? _onSessionRevoked;
  final void Function()? _onDeviceApprovalPending;

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
    final sameOrigin = serverOriginsMatch(
      request.uri,
      _expectedInstanceScope.origin,
    );
    if (sameOrigin && (statusCode == 401 || statusCode == 403)) {
      final failure = mapDioExceptionToFailure(err);
      if (statusCode == 403 &&
          failure.hasCode(DeviceApprovalErrorCode.pending)) {
        // Phiên còn chờ duyệt: giao diện chuyển sang màn chờ duyệt.
        _onDeviceApprovalPending?.call();
        handler.next(err);
        return;
      }
      if (statusCode == 401 &&
          failure.hasCode(SessionErrorCode.sessionRevoked) &&
          !request.path.contains('/api/v1/auth/refresh')) {
        // Phiên bị thu hồi: refresh cũng sẽ bị từ chối, xoá phiên ngay.
        await _handleSessionRevoked(request, failure);
        handler.next(err);
        return;
      }
    }
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

  Future<void> _handleSessionRevoked(
    RequestOptions request,
    Failure failure,
  ) async {
    final onRevoked = _onSessionRevoked;
    final guard = request.extra[_mutationGuardKey];
    if (onRevoked == null ||
        guard is! AuthTokenMutationGuard ||
        guard.instanceScopeId != _expectedInstanceScope.storageId ||
        !await _tokenRepository.isMutationGuardCurrent(guard)) {
      return;
    }
    // Request gửi bằng token cũ trong khi đã đăng nhập lại: không xoá phiên mới.
    final sentToken = _bearerToken(request.headers);
    final currentToken = (await _tokenRepository.readAccessTokenIfCurrent(
      guard,
    ))?.trim();
    if (sentToken != null &&
        currentToken != null &&
        currentToken.isNotEmpty &&
        sentToken != currentToken) {
      return;
    }
    await onRevoked(failure, guard);
  }
}

String? _bearerToken(Map<String, dynamic> headers) {
  for (final entry in headers.entries) {
    if (entry.key.toLowerCase() != 'authorization') {
      continue;
    }
    final value = entry.value?.toString().trim() ?? '';
    if (value.toLowerCase().startsWith('bearer ')) {
      return value.substring(7).trim();
    }
  }
  return null;
}

import '../../../../core/error/failure.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/auth_session.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../domain/repositories/auth_token_repository.dart';

/// Gọi khi máy chủ từ chối refresh (HTTP 401, mọi mã lỗi): phiên coi như bị
/// thu hồi (`SESSION_REVOKED`) hoặc phải đăng nhập lại (`RELOGIN_REQUIRED`).
typedef RefreshRejectedHandler =
    Future<void> Function(Failure failure, AuthTokenMutationGuard guard);

final class RefreshAccessTokenUseCase {
  RefreshAccessTokenUseCase({
    required AuthRepository authRepository,
    required AuthTokenRepository tokenRepository,
    RefreshRejectedHandler? onRefreshRejected,
  }) : _authRepository = authRepository,
       _tokenRepository = tokenRepository,
       _onRefreshRejected = onRefreshRejected;

  final AuthRepository _authRepository;
  final AuthTokenRepository _tokenRepository;
  final RefreshRejectedHandler? _onRefreshRejected;
  Future<Result<AuthSession>>? _inFlight;
  AuthTokenMutationGuard? _inFlightGuard;

  Future<Result<AuthSession>> execute({
    AuthTokenMutationGuard? expectedGuard,
  }) async {
    final guard =
        expectedGuard ?? await _tokenRepository.captureMutationGuard();
    if (guard == null ||
        !await _tokenRepository.isMutationGuardCurrent(guard)) {
      return const FailureResult(
        Failure(
          kind: FailureKind.unauthorized,
          message: 'Máy chủ đang hoạt động đã thay đổi.',
          code: 'AUTH_INSTANCE_CHANGED',
        ),
      );
    }

    final running = _inFlight;
    if (running != null && _inFlightGuard == guard) {
      return running;
    }

    final refresh = _refreshOnce(guard);
    _inFlight = refresh;
    _inFlightGuard = guard;
    try {
      return await refresh;
    } finally {
      if (identical(_inFlight, refresh)) {
        _inFlight = null;
        _inFlightGuard = null;
      }
    }
  }

  Future<Result<AuthSession>> _refreshOnce(AuthTokenMutationGuard guard) async {
    try {
      final refreshToken = (await _tokenRepository.readRefreshTokenIfCurrent(
        guard,
      ))?.trim();
      if (refreshToken == null || refreshToken.isEmpty) {
        return const FailureResult(
          Failure(
            kind: FailureKind.unauthorized,
            message: 'Phiên đăng nhập đã hết hạn.',
            code: 'REFRESH_TOKEN_MISSING',
          ),
        );
      }

      final result = await _authRepository.refresh(refreshToken);
      switch (result) {
        case Success<AuthSession>(:final value):
          if (!await _tokenRepository.saveTokensIfCurrent(
            value.tokens,
            guard,
          )) {
            return const FailureResult(
              Failure(
                kind: FailureKind.unauthorized,
                message: 'Máy chủ đang hoạt động đã thay đổi.',
                code: 'AUTH_INSTANCE_CHANGED',
              ),
            );
          }
          return result;
        case FailureResult<AuthSession>(failure: final failure):
          if (failure.requiresLogin) {
            // Xoá token + dữ liệu cục bộ (resetForLogout) rồi về đăng nhập.
            await _onRefreshRejected?.call(failure, guard);
            await _tokenRepository.clearTokensIfCurrent(guard);
          }
          return result;
      }
    } on Object catch (error) {
      return FailureResult(
        Failure(
          kind: FailureKind.storage,
          message: 'Không thể làm mới phiên đăng nhập.',
          code: 'REFRESH_STORAGE_FAILURE',
          cause: error,
        ),
      );
    }
  }
}

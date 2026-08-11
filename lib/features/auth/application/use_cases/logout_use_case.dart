import '../../../../core/error/failure.dart';
import '../../../../core/result/result.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../domain/repositories/auth_token_repository.dart';
import '../../domain/repositories/session_state_repository.dart';

final class LogoutUseCase {
  const LogoutUseCase({
    required AuthRepository authRepository,
    required AuthTokenRepository tokenRepository,
    required SessionStateRepository sessionStateRepository,
  }) : _authRepository = authRepository,
       _tokenRepository = tokenRepository,
       _sessionStateRepository = sessionStateRepository;

  final AuthRepository _authRepository;
  final AuthTokenRepository _tokenRepository;
  final SessionStateRepository _sessionStateRepository;

  Future<Result<void>> execute() async {
    try {
      final cleanupGuard = await _sessionStateRepository
          .captureActiveSessionGuard();
      final guard = await _tokenRepository.captureMutationGuard();
      if (cleanupGuard == null) {
        await _sessionStateRepository.resetForLogout();
        return const Success(null);
      }
      if (guard != null && guard == cleanupGuard) {
        final refreshToken = (await _tokenRepository.readRefreshTokenIfCurrent(
          guard,
        ))?.trim();
        if (refreshToken != null && refreshToken.isNotEmpty) {
          await _authRepository.logout(refreshToken);
        }
      }

      await _sessionStateRepository.resetForLogoutIfCurrent(cleanupGuard);
      return const Success(null);
    } on Object catch (error) {
      return FailureResult(
        Failure(
          kind: FailureKind.storage,
          message: 'Không thể xóa phiên đăng nhập khỏi thiết bị.',
          code: 'LOGOUT_LOCAL_CLEAR_FAILED',
          cause: error,
        ),
      );
    }
  }
}

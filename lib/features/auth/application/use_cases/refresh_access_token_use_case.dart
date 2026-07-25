import '../../../../core/error/failure.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/auth_session.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../domain/repositories/auth_token_repository.dart';

final class RefreshAccessTokenUseCase {
  RefreshAccessTokenUseCase({
    required AuthRepository authRepository,
    required AuthTokenRepository tokenRepository,
  }) : _authRepository = authRepository,
       _tokenRepository = tokenRepository;

  final AuthRepository _authRepository;
  final AuthTokenRepository _tokenRepository;
  Future<Result<AuthSession>>? _inFlight;

  Future<Result<AuthSession>> execute() {
    final running = _inFlight;
    if (running != null) {
      return running;
    }

    final refresh = _refreshOnce();
    _inFlight = refresh;
    return refresh.whenComplete(() {
      if (identical(_inFlight, refresh)) {
        _inFlight = null;
      }
    });
  }

  Future<Result<AuthSession>> _refreshOnce() async {
    try {
      final refreshToken = (await _tokenRepository.readRefreshToken())?.trim();
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
          await _tokenRepository.saveTokens(value.tokens);
          return result;
        case FailureResult<AuthSession>(failure: final failure):
          if (failure.requiresLogin) {
            await _tokenRepository.clearTokens();
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

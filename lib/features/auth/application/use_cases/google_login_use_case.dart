import '../../../../core/error/failure.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/auth_session.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../domain/repositories/auth_token_repository.dart';
import '../../domain/repositories/device_identity_repository.dart';
import '../../domain/repositories/google_identity_provider.dart';

final class GoogleLoginUseCase {
  const GoogleLoginUseCase({
    required GoogleIdentityProvider identityProvider,
    required AuthRepository authRepository,
    required AuthTokenRepository tokenRepository,
    required DeviceIdentityRepository deviceIdentityRepository,
  }) : _identityProvider = identityProvider,
       _authRepository = authRepository,
       _tokenRepository = tokenRepository,
       _deviceIdentityRepository = deviceIdentityRepository;

  final GoogleIdentityProvider _identityProvider;
  final AuthRepository _authRepository;
  final AuthTokenRepository _tokenRepository;
  final DeviceIdentityRepository _deviceIdentityRepository;

  Future<Result<AuthSession>> execute() async {
    final credentialResult = await _identityProvider.authenticate();
    if (credentialResult case FailureResult<String>(:final failure)) {
      return FailureResult(failure);
    }

    final credential = credentialResult.valueOrNull?.trim() ?? '';
    if (credential.isEmpty) {
      return const FailureResult(
        Failure(
          kind: FailureKind.unauthorized,
          code: 'GOOGLE_ID_TOKEN_MISSING',
          message: 'Google không trả về thông tin xác thực hợp lệ.',
        ),
      );
    }

    try {
      final device = await _deviceIdentityRepository.currentDevice();
      final result = await _authRepository.loginWithGoogle(
        credential: credential,
        device: device,
      );
      if (result case Success<AuthSession>(:final value)) {
        await _tokenRepository.saveTokens(value.tokens);
      }
      return result;
    } on Object catch (error) {
      return FailureResult(
        Failure(
          kind: FailureKind.storage,
          code: 'GOOGLE_LOGIN_STORAGE_FAILURE',
          message: 'Không thể lưu phiên đăng nhập Google an toàn.',
          cause: error,
        ),
      );
    }
  }
}

import '../../../../core/error/failure.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/auth_session.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../domain/repositories/auth_token_repository.dart';
import '../../domain/repositories/device_identity_repository.dart';

final class LoginCommand {
  const LoginCommand({
    required this.identifier,
    required this.password,
    this.remember = true,
  });

  final String identifier;
  final String password;
  final bool remember;
}

final class LoginUseCase {
  const LoginUseCase({
    required AuthRepository authRepository,
    required AuthTokenRepository tokenRepository,
    required DeviceIdentityRepository deviceIdentityRepository,
  }) : _authRepository = authRepository,
       _tokenRepository = tokenRepository,
       _deviceIdentityRepository = deviceIdentityRepository;

  final AuthRepository _authRepository;
  final AuthTokenRepository _tokenRepository;
  final DeviceIdentityRepository _deviceIdentityRepository;

  Future<Result<AuthSession>> execute(LoginCommand command) async {
    final identifier = command.identifier.trim();
    final password = command.password.trim();
    if (identifier.isEmpty || password.isEmpty) {
      return const FailureResult(
        Failure(
          kind: FailureKind.validation,
          message: 'Vui lòng nhập email/username và mật khẩu.',
          code: 'AUTH_INPUT_REQUIRED',
        ),
      );
    }

    try {
      final guard = await _tokenRepository.captureMutationGuard();
      if (guard == null) {
        throw StateError('Active instance is not live validated.');
      }
      final device = await _deviceIdentityRepository.currentDevice();
      if (await _tokenRepository.captureMutationGuard() != guard) {
        throw StateError('Active instance changed during login.');
      }
      final result = await _authRepository.login(
        identifier: identifier,
        password: password,
        device: device,
      );

      if (result case Success<AuthSession>(:final value)) {
        if (!await _tokenRepository.saveTokensIfCurrent(
          value.tokens,
          guard,
          persistence: command.remember
              ? AuthTokenPersistence.durable
              : AuthTokenPersistence.sessionOnly,
        )) {
          throw StateError('Active instance changed during login.');
        }
      }
      return result;
    } on Object catch (error) {
      return FailureResult(_storageFailure(error));
    }
  }
}

Failure _storageFailure(Object error) {
  return Failure(
    kind: FailureKind.storage,
    message: 'Không thể lưu phiên đăng nhập an toàn.',
    code: 'AUTH_STORAGE_FAILURE',
    cause: error,
  );
}

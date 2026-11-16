import '../../../../core/error/failure.dart';
import '../../../../core/result/result.dart';
import '../../../../l10n/app_strings.dart';
import '../../domain/entities/auth_session.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../domain/repositories/auth_token_repository.dart';
import '../../domain/repositories/device_identity_repository.dart';

final class RegisterCommand {
  const RegisterCommand({
    required this.displayName,
    required this.email,
    required this.username,
    required this.password,
    required this.confirmPassword,
    this.inviteToken = '',
    this.termsAccepted = false,
    this.termsVersion = '',
    this.privacyAccepted = false,
    this.privacyVersion = '',
    this.remember = true,
  });

  final String displayName;
  final String email;
  final String username;
  final String password;
  final String confirmPassword;
  final String inviteToken;
  final bool termsAccepted;
  final String termsVersion;
  final bool privacyAccepted;
  final String privacyVersion;
  final bool remember;
}

final class RegisterUseCase {
  const RegisterUseCase({
    required AuthRepository authRepository,
    required AuthTokenRepository tokenRepository,
    required DeviceIdentityRepository deviceIdentityRepository,
  }) : _authRepository = authRepository,
       _tokenRepository = tokenRepository,
       _deviceIdentityRepository = deviceIdentityRepository;

  final AuthRepository _authRepository;
  final AuthTokenRepository _tokenRepository;
  final DeviceIdentityRepository _deviceIdentityRepository;

  Future<Result<AuthSession>> execute(RegisterCommand command) async {
    final displayName = command.displayName.trim();
    final email = command.email.trim();
    final username = command.username.trim();
    final password = command.password.trim();
    final confirmPassword = command.confirmPassword.trim();
    final inviteToken = command.inviteToken.trim();
    final termsVersion = command.termsVersion.trim();
    final privacyVersion = command.privacyVersion.trim();

    if (displayName.isEmpty || email.isEmpty || username.isEmpty) {
      return FailureResult(
        Failure(
          kind: FailureKind.validation,
          message: tr(
            'Vui lòng nhập đủ họ tên, email và username.',
            'Enter your full name, email and username.',
          ),
          code: 'REGISTER_PROFILE_REQUIRED',
        ),
      );
    }
    if (!email.contains('@') || !email.contains('.')) {
      return FailureResult(
        Failure(
          kind: FailureKind.validation,
          message: tr('Email không hợp lệ.', 'Invalid email.'),
          code: 'REGISTER_EMAIL_INVALID',
        ),
      );
    }
    if (password.length < 8) {
      return FailureResult(
        Failure(
          kind: FailureKind.validation,
          message: tr(
            'Mật khẩu cần tối thiểu 8 ký tự.',
            'The password must have at least 8 characters.',
          ),
          code: 'REGISTER_PASSWORD_SHORT',
        ),
      );
    }
    if (password != confirmPassword) {
      return FailureResult(
        Failure(
          kind: FailureKind.validation,
          message: tr(
            'Mật khẩu xác nhận không khớp.',
            'The passwords do not match.',
          ),
          code: 'REGISTER_PASSWORD_MISMATCH',
        ),
      );
    }
    if (!command.termsAccepted ||
        !command.privacyAccepted ||
        termsVersion.isEmpty ||
        privacyVersion.isEmpty) {
      return FailureResult(
        Failure(
          kind: FailureKind.validation,
          message: tr(
            'Bạn cần đồng ý với Điều khoản sử dụng và Chính sách quyền riêng tư.',
            'You need to accept the Terms of Use and Privacy Policy.',
          ),
          code: 'REGISTER_LEGAL_ACCEPTANCE_REQUIRED',
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
        throw StateError('Active instance changed during registration.');
      }
      final result = await _authRepository.register(
        displayName: displayName,
        email: email,
        username: username,
        password: password,
        inviteToken: inviteToken,
        termsAccepted: command.termsAccepted,
        termsVersion: termsVersion,
        privacyAccepted: command.privacyAccepted,
        privacyVersion: privacyVersion,
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
          throw StateError('Active instance changed during registration.');
        }
      }
      return result;
    } on Object catch (error) {
      return FailureResult(
        Failure(
          kind: FailureKind.storage,
          message: tr(
            'Không thể lưu phiên đăng ký an toàn.',
            'Could not save your registration session securely.',
          ),
          code: 'REGISTER_STORAGE_FAILURE',
          cause: error,
        ),
      );
    }
  }
}

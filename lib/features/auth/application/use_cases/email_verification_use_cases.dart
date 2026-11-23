import '../../../../core/error/failure.dart';
import '../../../../core/result/result.dart';
import '../../../../l10n/app_strings.dart';
import '../../domain/entities/auth_session.dart';
import '../../domain/entities/email_verification.dart';
import '../../domain/repositories/auth_token_repository.dart';
import '../../domain/repositories/device_identity_repository.dart';
import '../../domain/repositories/email_verification_repository.dart';
import 'login_mfa_use_cases.dart';

final _codePattern = RegExp(r'^\d{6}$');

/// Nhập mã 6 số → nhận phiên đăng nhập (giống `/auth/login`) và lưu token an
/// toàn theo đúng máy chủ đang hoạt động.
final class VerifyEmailCodeUseCase {
  const VerifyEmailCodeUseCase({
    required EmailVerificationRepository repository,
    required AuthTokenRepository tokenRepository,
    required DeviceIdentityRepository deviceIdentityRepository,
  }) : _repository = repository,
       _tokenRepository = tokenRepository,
       _deviceIdentityRepository = deviceIdentityRepository;

  final EmailVerificationRepository _repository;
  final AuthTokenRepository _tokenRepository;
  final DeviceIdentityRepository _deviceIdentityRepository;

  Future<Result<AuthSession>> execute({
    required String verificationId,
    required String code,
  }) async {
    final cleanCode = code.replaceAll(RegExp(r'\s'), '');
    if (!_codePattern.hasMatch(cleanCode)) {
      return FailureResult(
        Failure(
          kind: FailureKind.validation,
          message: tr(
            'Mã xác minh gồm đúng 6 chữ số.',
            'The verification code has exactly 6 digits.',
          ),
          code: 'EMAIL_CODE_FORMAT',
        ),
      );
    }
    try {
      final guard = await _tokenRepository.captureMutationGuard();
      if (guard == null) {
        throw StateError('Active instance is not live validated.');
      }
      final device = await _deviceIdentityRepository.currentDevice();
      final result = await _repository.verify(
        verificationId: verificationId,
        code: cleanCode,
        device: device,
      );
      if (result case Success<AuthSession>(:final value)) {
        if (!await _tokenRepository.saveTokensIfCurrent(
          value.tokens,
          guard,
          persistence: AuthTokenPersistence.durable,
        )) {
          throw StateError('Active instance changed during verification.');
        }
      }
      if (result case FailureResult<AuthSession>(:final failure)) {
        return FailureResult(
          attachLoginMfaChallenge(failure, guard: guard, remember: true),
        );
      }
      return result;
    } on Object catch (error) {
      return FailureResult(
        Failure(
          kind: FailureKind.storage,
          message: tr(
            'Không thể lưu phiên đăng nhập an toàn.',
            'Could not save your session securely.',
          ),
          code: 'AUTH_STORAGE_FAILURE',
          cause: error,
        ),
      );
    }
  }
}

final class ResendEmailCodeUseCase {
  const ResendEmailCodeUseCase(this._repository);

  final EmailVerificationRepository _repository;

  Future<Result<EmailVerificationTicket>> execute(String verificationId) {
    return _repository.resend(verificationId);
  }
}

/// Câu báo lỗi cho màn nhập mã.
String emailVerificationFailureMessage(Failure failure) {
  if (failure.hasCode(EmailVerificationErrorCode.codeInvalid)) {
    final left = int.tryParse('${failure.details['attempts_left'] ?? ''}');
    return left == null
        ? tr('Mã xác minh chưa đúng.', 'The verification code is incorrect.')
        : left <= 0
        ? tr(
            'Mã xác minh chưa đúng. Bạn đã hết lượt thử, hãy gửi lại mã mới.',
            'The verification code is incorrect. You are out of attempts, so request a new code.',
          )
        : tr(
            'Mã xác minh chưa đúng. Còn $left lần thử.',
            'The verification code is incorrect. $left attempts left.',
          );
  }
  if (failure.hasCode(EmailVerificationErrorCode.codeLocked)) {
    return tr(
      'Bạn đã nhập sai quá nhiều lần. Hãy gửi lại mã mới.',
      'Too many incorrect attempts. Request a new code.',
    );
  }
  if (failure.hasCode(EmailVerificationErrorCode.codeExpired)) {
    return tr(
      'Mã xác minh đã hết hạn. Hãy gửi lại mã mới.',
      'The verification code has expired. Request a new code.',
    );
  }
  if (failure.hasCode(EmailVerificationErrorCode.notFound)) {
    return tr(
      'Phiên xác minh không còn. Hãy đăng ký hoặc đăng nhập lại.',
      'The verification session is gone. Sign up or sign in again.',
    );
  }
  if (failure.hasCode(EmailVerificationErrorCode.resendTooSoon)) {
    return tr(
      'Bạn vừa yêu cầu gửi mã. Vui lòng chờ rồi thử lại.',
      'You just requested a code. Please wait and try again.',
    );
  }
  return failure.message;
}

/// Số giây phải chờ trong `EMAIL_RESEND_TOO_SOON` (`details.retry_after_seconds`).
int? retryAfterSeconds(Failure failure) {
  final value = failure.details['retry_after_seconds'];
  final seconds = value is num ? value.toInt() : int.tryParse('${value ?? ''}');
  return seconds == null || seconds < 0 ? null : seconds;
}

/// Câu báo khi đăng ký bằng email ngoài tên miền tổ chức cho phép.
String emailDomainNotAllowedMessage(Failure failure) {
  final serverMessage = failure.message.trim();
  final hasVietnamese = serverMessage.runes.any((rune) => rune > 0x7f);
  return hasVietnamese
      ? serverMessage
      : tr(
          'Email này không thuộc tên miền công ty được phép đăng ký. '
              'Hãy dùng email công ty hoặc liên hệ quản trị viên.',
          'This email is not on a company domain that is allowed to register. '
              'Use your company email or contact an administrator.',
        );
}

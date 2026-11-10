import '../../../../core/error/failure.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/auth_session.dart';
import '../../domain/entities/email_verification.dart';
import '../../domain/repositories/auth_token_repository.dart';
import '../../domain/repositories/device_identity_repository.dart';
import '../../domain/repositories/email_verification_repository.dart';

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
      return const FailureResult(
        Failure(
          kind: FailureKind.validation,
          message: 'Mã xác minh gồm đúng 6 chữ số.',
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
      return result;
    } on Object catch (error) {
      return FailureResult(
        Failure(
          kind: FailureKind.storage,
          message: 'Không thể lưu phiên đăng nhập an toàn.',
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
        ? 'Mã xác minh chưa đúng.'
        : left <= 0
        ? 'Mã xác minh chưa đúng. Bạn đã hết lượt thử, hãy gửi lại mã mới.'
        : 'Mã xác minh chưa đúng. Còn $left lần thử.';
  }
  if (failure.hasCode(EmailVerificationErrorCode.codeLocked)) {
    return 'Bạn đã nhập sai quá nhiều lần. Hãy gửi lại mã mới.';
  }
  if (failure.hasCode(EmailVerificationErrorCode.codeExpired)) {
    return 'Mã xác minh đã hết hạn. Hãy gửi lại mã mới.';
  }
  if (failure.hasCode(EmailVerificationErrorCode.notFound)) {
    return 'Phiên xác minh không còn. Hãy đăng ký hoặc đăng nhập lại.';
  }
  if (failure.hasCode(EmailVerificationErrorCode.resendTooSoon)) {
    return 'Bạn vừa yêu cầu gửi mã. Vui lòng chờ rồi thử lại.';
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
      : 'Email này không thuộc tên miền công ty được phép đăng ký. '
            'Hãy dùng email công ty hoặc liên hệ quản trị viên.';
}

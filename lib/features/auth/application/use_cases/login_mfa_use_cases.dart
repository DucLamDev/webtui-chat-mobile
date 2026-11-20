import '../../../../core/error/failure.dart';
import '../../../../core/result/result.dart';
import '../../../../l10n/app_strings.dart';
import '../../domain/entities/auth_session.dart';
import '../../domain/entities/login_mfa.dart';
import '../../domain/repositories/auth_token_repository.dart';
import '../../domain/repositories/login_mfa_repository.dart';

/// Lỗi `MFA_REQUIRED` hợp lệ thì gắn lượt chờ [LoginMfaChallenge] (ràng với máy
/// chủ đang hoạt động) vào `Failure.cause`; lỗi khác giữ nguyên.
Failure attachLoginMfaChallenge(
  Failure failure, {
  required AuthTokenMutationGuard guard,
  required bool remember,
  DateTime? now,
}) {
  if (!failure.hasCode(LoginMfaErrorCode.required)) return failure;
  final challenge = LoginMfaChallenge.fromDetails(
    failure.details,
    instanceScopeId: guard.instanceScopeId,
    remember: remember,
    now: now ?? DateTime.now(),
  );
  if (challenge == null) {
    return failure.copyWith(
      message: tr(
        'Máy chủ yêu cầu xác thực hai lớp nhưng phản hồi không hợp lệ. Vui lòng thử lại.',
        'The server requires two-factor verification but its response is not valid. Please try again.',
      ),
    );
  }
  return failure.copyWith(cause: challenge);
}

/// Lượt chờ xác thực hai lớp gắn trong lỗi đăng nhập (nếu có).
LoginMfaChallenge? loginMfaChallengeOf(Failure failure) {
  final cause = failure.cause;
  return cause is LoginMfaChallenge ? cause : null;
}

/// Lượt đã hết hạn / bị huỷ: phải quay lại bước mật khẩu.
bool loginMfaMustRestart(Failure failure) =>
    failure.hasCode(LoginMfaErrorCode.challengeExpired) ||
    failure.hasCode(LoginMfaErrorCode.tooManyAttempts) ||
    failure.hasCode(_instanceChangedCode);

int? loginMfaAttemptsLeft(Failure failure) {
  final value = failure.details['attempts_left'];
  return value is num ? value.toInt() : int.tryParse('${value ?? ''}');
}

String loginMfaFailureMessage(Failure failure) {
  if (failure.hasCode(LoginMfaErrorCode.invalidCode)) {
    final left = loginMfaAttemptsLeft(failure);
    return left == null || left <= 0
        ? tr(
            'Mã không đúng hoặc đã dùng.',
            'The code is incorrect or was already used.',
          )
        : tr(
            'Mã không đúng hoặc đã dùng. Còn $left lần thử.',
            'The code is incorrect or was already used. $left attempts left.',
          );
  }
  if (failure.hasCode(LoginMfaErrorCode.challengeExpired)) {
    return tr(
      'Lượt đăng nhập đã hết hạn. Vui lòng nhập lại mật khẩu.',
      'This sign-in has expired. Please enter your password again.',
    );
  }
  if (failure.hasCode(LoginMfaErrorCode.tooManyAttempts)) {
    return tr(
      'Bạn đã nhập sai quá nhiều lần. Vui lòng đăng nhập lại sau ít phút.',
      'Too many incorrect attempts. Please sign in again in a few minutes.',
    );
  }
  if (failure.hasCode(LoginMfaErrorCode.methodNotAvailable)) {
    return tr(
      'Tài khoản không dùng được cách xác thực này. Hãy chọn cách khác.',
      'This verification method is not available for the account. Choose another one.',
    );
  }
  if (failure.hasCode('AUTH_TEMPORARILY_UNAVAILABLE')) {
    return tr(
      'Bạn thử quá nhanh. Vui lòng đợi ít phút rồi thử lại.',
      'You are trying too fast. Please wait a few minutes and try again.',
    );
  }
  return failure.message;
}

const _instanceChangedCode = 'AUTH_INSTANCE_CHANGED';
final _totpPattern = RegExp(r'^\d{6}$');

/// Chuẩn hoá mã người dùng nhập: TOTP chỉ giữ chữ số; mã khôi phục viết hoa,
/// bỏ khoảng trắng / ký tự lạ.
String normalizeLoginMfaCode(LoginMfaMethod method, String value) {
  return switch (method) {
    LoginMfaMethod.totp => value.replaceAll(RegExp(r'\D'), ''),
    LoginMfaMethod.recoveryCode => value.toUpperCase().replaceAll(
      RegExp(r'[^A-Z0-9-]'),
      '',
    ),
    LoginMfaMethod.passkey => '',
  };
}

bool loginMfaCodeReady(LoginMfaMethod method, String code) {
  return switch (method) {
    LoginMfaMethod.totp => _totpPattern.hasMatch(code),
    LoginMfaMethod.recoveryCode =>
      code.replaceAll('-', '').length >= 10 && code.length <= 32,
    LoginMfaMethod.passkey => false,
  };
}

/// Cách nhập mã mở sẵn khi vào bước xác thực: ứng dụng xác thực nếu có, không
/// thì mã khôi phục; tài khoản chỉ có passkey thì null.
LoginMfaMethod? defaultLoginMfaMethod(LoginMfaChallenge challenge) =>
    challenge.usableMethods.firstOrNull;

/// Mọi cách xác thực của tài khoản, theo thứ tự hiện trong danh sách chọn
/// (gồm cả passkey dù ứng dụng chưa dùng được).
List<LoginMfaMethod> loginMfaMethodChoices(LoginMfaChallenge challenge) => [
  for (final method in LoginMfaMethod.values)
    if (challenge.methods.contains(method)) method,
];

/// Chỉ nhắc thời hạn khi lượt xác thực còn dưới một phút.
const loginMfaCountdownThresholdSeconds = 60;

bool shouldShowLoginMfaCountdown(int secondsLeft) =>
    secondsLeft > 0 && secondsLeft < loginMfaCountdownThresholdSeconds;

final _digitSeparator = RegExp(r'(?<=\d)[\s\-\u2010-\u2015.·]+(?=\d)');
final _digitRun = RegExp(r'\d+');

/// Lấy mã 6 số từ chữ người dùng gõ hoặc dán: bỏ dấu cách / gạch giữa các chữ
/// số (`123 456`, `123-456`); dán cả câu có đúng một dãy 6 số thì lấy dãy đó.
String extractLoginTotpCode(String raw) {
  final compact = raw.replaceAll(_digitSeparator, '');
  final runs = [for (final match in _digitRun.allMatches(compact)) match[0]!];
  final sixDigitRuns = runs.where((run) => run.length == 6).toList();
  if (runs.length > 1 && sixDigitRuns.length == 1) return sixDigitRuns.single;
  final digits = runs.join();
  return digits.length > 6 ? digits.substring(0, 6) : digits;
}

/// Định dạng mã khôi phục khi gõ: chữ in hoa, tự chèn gạch sau 5 ký tự
/// (`XXXXX-XXXXX`), tối đa 10 ký tự chữ / số.
String formatRecoveryCodeInput(String raw) {
  final chars = raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  final limited = chars.length > 10 ? chars.substring(0, 10) : chars;
  if (limited.length <= 5) return limited;
  return '${limited.substring(0, 5)}-${limited.substring(5)}';
}

/// Gửi mã của bước xác thực hai lớp; đúng thì lưu phiên theo đúng máy chủ và
/// lựa chọn ghi nhớ của bước trước.
final class CompleteLoginMfaUseCase {
  const CompleteLoginMfaUseCase({
    required LoginMfaRepository repository,
    required AuthTokenRepository tokenRepository,
    DateTime Function()? clock,
  }) : _repository = repository,
       _tokenRepository = tokenRepository,
       _clock = clock ?? DateTime.now;

  final LoginMfaRepository _repository;
  final AuthTokenRepository _tokenRepository;
  final DateTime Function() _clock;

  Future<Result<AuthSession>> execute({
    required LoginMfaChallenge challenge,
    required LoginMfaMethod method,
    required String code,
  }) async {
    if (!method.supportedInApp) {
      return FailureResult(
        Failure(
          kind: FailureKind.validation,
          code: LoginMfaErrorCode.methodUnsupported,
          message: tr(
            'Ứng dụng chưa hỗ trợ passkey. Hãy dùng mã khôi phục hoặc đăng nhập trên web.',
            'The app does not support passkeys yet. Use a recovery code or sign in on the web.',
          ),
        ),
      );
    }
    if (!challenge.methods.contains(method)) {
      return FailureResult(
        Failure(
          kind: FailureKind.validation,
          code: LoginMfaErrorCode.methodNotAvailable,
          message: loginMfaFailureMessage(
            const Failure(
              kind: FailureKind.validation,
              message: '',
              code: LoginMfaErrorCode.methodNotAvailable,
            ),
          ),
        ),
      );
    }
    final cleanCode = normalizeLoginMfaCode(method, code);
    if (!loginMfaCodeReady(method, cleanCode)) {
      return FailureResult(
        Failure(
          kind: FailureKind.validation,
          code: 'MFA_CODE_FORMAT',
          message: method == LoginMfaMethod.totp
              ? tr(
                  'Mã xác thực gồm đúng 6 chữ số.',
                  'The verification code has exactly 6 digits.',
                )
              : tr(
                  'Mã khôi phục có dạng XXXXX-XXXXX.',
                  'A recovery code looks like XXXXX-XXXXX.',
                ),
        ),
      );
    }
    if (challenge.isExpired(_clock())) {
      return FailureResult(
        Failure(
          kind: FailureKind.unauthorized,
          code: LoginMfaErrorCode.challengeExpired,
          message: loginMfaFailureMessage(
            const Failure(
              kind: FailureKind.unauthorized,
              message: '',
              code: LoginMfaErrorCode.challengeExpired,
            ),
          ),
        ),
      );
    }
    try {
      final guard = await _tokenRepository.captureMutationGuard();
      if (guard == null || guard.instanceScopeId != challenge.instanceScopeId) {
        return FailureResult(
          Failure(
            kind: FailureKind.unauthorized,
            code: _instanceChangedCode,
            message: tr(
              'Máy chủ đang hoạt động đã thay đổi. Vui lòng đăng nhập lại.',
              'The active server has changed. Please sign in again.',
            ),
          ),
        );
      }
      final result = await _repository.complete(
        mfaToken: challenge.mfaToken,
        method: method,
        code: cleanCode,
      );
      if (result case Success<AuthSession>(:final value)) {
        if (!await _tokenRepository.saveTokensIfCurrent(
          value.tokens,
          guard,
          persistence: challenge.remember
              ? AuthTokenPersistence.durable
              : AuthTokenPersistence.sessionOnly,
        )) {
          throw StateError('Active instance changed during MFA sign-in.');
        }
      }
      return result;
    } on Object catch (error) {
      return FailureResult(
        Failure(
          kind: FailureKind.storage,
          code: 'AUTH_STORAGE_FAILURE',
          message: tr(
            'Không thể lưu phiên đăng nhập an toàn.',
            'Could not save your session securely.',
          ),
          cause: error,
        ),
      );
    }
  }
}

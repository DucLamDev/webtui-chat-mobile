import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/result/result.dart';
import '../../application/use_cases/email_verification_use_cases.dart';
import '../../domain/entities/auth_session.dart';
import '../../domain/entities/email_verification.dart';

final class EmailVerificationState {
  const EmailVerificationState({
    required this.ticket,
    required this.countdown,
    this.code = '',
    this.isVerifying = false,
    this.isResending = false,
    this.errorMessage,
    this.infoMessage,
    this.mustResend = false,
    this.verifiedSession,
  });

  final EmailVerificationTicket ticket;
  final ResendCountdown countdown;
  final String code;
  final bool isVerifying;
  final bool isResending;
  final String? errorMessage;
  final String? infoMessage;

  /// Mã đã khoá / hết hạn: phải gửi lại mã mới mới nhập tiếp được.
  final bool mustResend;

  /// Xác minh xong: phiên đăng nhập (có thể còn chờ duyệt thiết bị).
  final AuthSession? verifiedSession;

  bool get canSubmit =>
      !isVerifying &&
      !mustResend &&
      verifiedSession == null &&
      RegExp(r'^\d{6}$').hasMatch(code);

  EmailVerificationState copyWith({
    EmailVerificationTicket? ticket,
    ResendCountdown? countdown,
    String? code,
    bool? isVerifying,
    bool? isResending,
    String? errorMessage,
    bool clearError = false,
    String? infoMessage,
    bool clearInfo = false,
    bool? mustResend,
    AuthSession? verifiedSession,
  }) {
    return EmailVerificationState(
      ticket: ticket ?? this.ticket,
      countdown: countdown ?? this.countdown,
      code: code ?? this.code,
      isVerifying: isVerifying ?? this.isVerifying,
      isResending: isResending ?? this.isResending,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      infoMessage: clearInfo ? null : infoMessage ?? this.infoMessage,
      mustResend: mustResend ?? this.mustResend,
      verifiedSession: verifiedSession ?? this.verifiedSession,
    );
  }
}

final class EmailVerificationController
    extends StateNotifier<EmailVerificationState> {
  EmailVerificationController({
    required EmailVerificationTicket ticket,
    required Future<Result<AuthSession>> Function({
      required String verificationId,
      required String code,
    })
    verify,
    required Future<Result<EmailVerificationTicket>> Function(
      String verificationId,
    )
    resend,
    DateTime Function()? clock,
  }) : _verify = verify,
       _resend = resend,
       _clock = clock ?? DateTime.now,
       super(
         EmailVerificationState(
           ticket: ticket,
           countdown: ResendCountdown(availableAt: ticket.resendAvailableAt),
         ),
       );

  final Future<Result<AuthSession>> Function({
    required String verificationId,
    required String code,
  })
  _verify;
  final Future<Result<EmailVerificationTicket>> Function(String verificationId)
  _resend;
  final DateTime Function() _clock;

  int resendSecondsLeft() => state.countdown.secondsLeft(_clock());

  void updateCode(String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    state = state.copyWith(
      code: digits.length > 6 ? digits.substring(0, 6) : digits,
      clearError: true,
    );
  }

  Future<void> submit() async {
    if (!state.canSubmit) return;
    state = state.copyWith(
      isVerifying: true,
      clearError: true,
      clearInfo: true,
    );
    final result = await _verify(
      verificationId: state.ticket.verificationId,
      code: state.code,
    );
    if (!mounted) return;
    switch (result) {
      case Success<AuthSession>(:final value):
        state = state.copyWith(isVerifying: false, verifiedSession: value);
      case FailureResult<AuthSession>(:final failure):
        final mustResend =
            failure.hasCode(EmailVerificationErrorCode.codeLocked) ||
            failure.hasCode(EmailVerificationErrorCode.codeExpired) ||
            (failure.hasCode(EmailVerificationErrorCode.codeInvalid) &&
                _attemptsLeft(failure) == 0);
        state = state.copyWith(
          isVerifying: false,
          code: '',
          errorMessage: emailVerificationFailureMessage(failure),
          mustResend: mustResend,
        );
    }
  }

  Future<void> resend() async {
    if (state.isResending || resendSecondsLeft() > 0) return;
    state = state.copyWith(
      isResending: true,
      clearError: true,
      clearInfo: true,
    );
    final result = await _resend(state.ticket.verificationId);
    if (!mounted) return;
    final now = _clock();
    switch (result) {
      case Success<EmailVerificationTicket>(value: final ticket):
        state = state.copyWith(
          isResending: false,
          ticket: ticket,
          mustResend: false,
          code: '',
          countdown: ticket.resendAvailableAt == null
              ? ResendCountdown.after(60, now: now)
              : ResendCountdown(availableAt: ticket.resendAvailableAt),
          infoMessage:
              'Đã gửi mã mới tới ${ticket.emailHint ?? 'email của bạn'}.',
        );
      case FailureResult<EmailVerificationTicket>(:final failure):
        final retryAfter = retryAfterSeconds(failure);
        state = state.copyWith(
          isResending: false,
          errorMessage: emailVerificationFailureMessage(failure),
          countdown: retryAfter == null
              ? null
              : ResendCountdown.after(retryAfter, now: now),
        );
    }
  }
}

int? _attemptsLeft(Failure failure) {
  final value = failure.details['attempts_left'];
  return value is num ? value.toInt() : int.tryParse('${value ?? ''}');
}

final emailVerificationControllerProvider = StateNotifierProvider.autoDispose
    .family<
      EmailVerificationController,
      EmailVerificationState,
      EmailVerificationTicket
    >((ref, ticket) {
      return EmailVerificationController(
        ticket: ticket,
        verify: ({required verificationId, required code}) => ref
            .read(verifyEmailCodeUseCaseProvider)
            .execute(verificationId: verificationId, code: code),
        resend: (verificationId) =>
            ref.read(resendEmailCodeUseCaseProvider).execute(verificationId),
      );
    });

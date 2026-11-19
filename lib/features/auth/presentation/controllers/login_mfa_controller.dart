import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/result/result.dart';
import '../../application/use_cases/login_mfa_use_cases.dart';
import '../../domain/entities/auth_session.dart';
import '../../domain/entities/login_mfa.dart';
import 'auth_flow_providers.dart';

typedef CompleteLoginMfa =
    Future<Result<AuthSession>> Function({
      required LoginMfaChallenge challenge,
      required LoginMfaMethod method,
      required String code,
    });

final class LoginMfaState {
  const LoginMfaState({
    required this.challenge,
    required this.method,
    this.code = '',
    this.isSubmitting = false,
    this.errorMessage,
    this.mustRestart = false,
    this.session,
  });

  /// null khi mở màn mà không còn lượt chờ (đã dùng / app khởi động lại).
  final LoginMfaChallenge? challenge;

  /// null khi tài khoản chỉ có passkey (app chưa hỗ trợ).
  final LoginMfaMethod? method;
  final String code;
  final bool isSubmitting;
  final String? errorMessage;

  /// Lượt hết hạn / bị huỷ: chỉ còn quay lại bước mật khẩu.
  final bool mustRestart;

  /// Xác thực xong: phiên đăng nhập (có thể còn chờ duyệt thiết bị).
  final AuthSession? session;

  bool get canSwitchMethod =>
      !isSubmitting &&
      !mustRestart &&
      session == null &&
      (challenge?.usableMethods.length ?? 0) > 1;

  bool get canSubmit {
    final selected = method;
    return challenge != null &&
        selected != null &&
        !isSubmitting &&
        !mustRestart &&
        session == null &&
        loginMfaCodeReady(selected, code);
  }

  LoginMfaState copyWith({
    LoginMfaMethod? method,
    String? code,
    bool? isSubmitting,
    String? errorMessage,
    bool clearError = false,
    bool? mustRestart,
    AuthSession? session,
  }) {
    return LoginMfaState(
      challenge: challenge,
      method: method ?? this.method,
      code: code ?? this.code,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      mustRestart: mustRestart ?? this.mustRestart,
      session: session ?? this.session,
    );
  }
}

final class LoginMfaController extends StateNotifier<LoginMfaState> {
  LoginMfaController({
    required LoginMfaChallenge? challenge,
    required CompleteLoginMfa complete,
    DateTime Function()? clock,
  }) : _complete = complete,
       _clock = clock ?? DateTime.now,
       super(
         LoginMfaState(
           challenge: challenge,
           method: challenge == null || challenge.usableMethods.isEmpty
               ? null
               : challenge.usableMethods.first,
         ),
       );

  @visibleForTesting
  factory LoginMfaController.forTesting({
    required LoginMfaChallenge? challenge,
    required CompleteLoginMfa complete,
    DateTime Function()? clock,
  }) => LoginMfaController(
    challenge: challenge,
    complete: complete,
    clock: clock,
  );

  final CompleteLoginMfa _complete;
  final DateTime Function() _clock;

  int secondsLeft() => state.challenge?.secondsLeft(_clock()) ?? 0;

  void selectMethod(LoginMfaMethod method) {
    if (!state.canSwitchMethod ||
        state.method == method ||
        !(state.challenge?.usableMethods.contains(method) ?? false)) {
      return;
    }
    state = state.copyWith(method: method, code: '', clearError: true);
  }

  void updateCode(String value) {
    final method = state.method;
    if (method == null || state.isSubmitting) return;
    final normalized = normalizeLoginMfaCode(method, value);
    final limit = method == LoginMfaMethod.totp ? 6 : 11;
    state = state.copyWith(
      code: normalized.length > limit
          ? normalized.substring(0, limit)
          : normalized,
      clearError: true,
    );
  }

  Future<void> submit() async {
    final challenge = state.challenge;
    final method = state.method;
    if (!state.canSubmit || challenge == null || method == null) return;
    state = state.copyWith(isSubmitting: true, clearError: true);
    final result = await _complete(
      challenge: challenge,
      method: method,
      code: state.code,
    );
    if (!mounted) return;
    switch (result) {
      case Success<AuthSession>(:final value):
        state = state.copyWith(isSubmitting: false, session: value);
      case FailureResult<AuthSession>(:final failure):
        state = state.copyWith(
          isSubmitting: false,
          code: '',
          errorMessage: loginMfaFailureMessage(failure),
          mustRestart: _mustRestart(failure),
        );
    }
  }

  bool _mustRestart(Failure failure) {
    if (loginMfaMustRestart(failure)) return true;
    // Hết lượt thử thì máy chủ đã huỷ lượt đăng nhập.
    return failure.hasCode(LoginMfaErrorCode.invalidCode) &&
        loginMfaAttemptsLeft(failure) == 0;
  }
}

final loginMfaControllerProvider =
    StateNotifierProvider.autoDispose<LoginMfaController, LoginMfaState>((ref) {
      final useCase = ref.read(completeLoginMfaUseCaseProvider);
      return LoginMfaController(
        challenge: ref.read(pendingLoginMfaChallengeProvider),
        complete: ({required challenge, required method, required code}) =>
            useCase.execute(challenge: challenge, method: method, code: code),
      );
    });

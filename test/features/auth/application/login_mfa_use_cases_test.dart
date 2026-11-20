import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/error/failure.dart';
import 'package:webtui_chat/core/result/result.dart';
import 'package:webtui_chat/features/auth/application/use_cases/login_mfa_use_cases.dart';
import 'package:webtui_chat/features/auth/domain/entities/auth_session.dart';
import 'package:webtui_chat/features/auth/domain/entities/auth_tokens.dart';
import 'package:webtui_chat/features/auth/domain/entities/login_mfa.dart';
import 'package:webtui_chat/features/auth/domain/repositories/auth_token_repository.dart';
import 'package:webtui_chat/features/auth/domain/repositories/login_mfa_repository.dart';

final _now = DateTime.utc(2026, 11, 19, 8);

LoginMfaChallenge _challenge({
  List<LoginMfaMethod> methods = const [
    LoginMfaMethod.totp,
    LoginMfaMethod.recoveryCode,
  ],
  bool remember = true,
  String scope = 'scope-a',
}) {
  return LoginMfaChallenge(
    mfaToken: 'mfa-token-1',
    methods: methods,
    expiresAt: _now.add(const Duration(minutes: 5)),
    instanceScopeId: scope,
    remember: remember,
  );
}

void main() {
  test(
    'correct TOTP code saves the session with the remembered policy',
    () async {
      final repository = _FakeLoginMfaRepository();
      final tokens = _FakeTokenRepository();
      final useCase = CompleteLoginMfaUseCase(
        repository: repository,
        tokenRepository: tokens,
        clock: () => _now,
      );

      final result = await useCase.execute(
        challenge: _challenge(remember: false),
        method: LoginMfaMethod.totp,
        code: ' 123 456 ',
      );

      expect(result.isSuccess, isTrue);
      expect(repository.calls, ['mfa-token-1|totp|123456']);
      expect(tokens.accessToken, 'access-mfa');
      expect(tokens.lastPersistence, AuthTokenPersistence.sessionOnly);
    },
  );

  test('recovery code is normalised before sending', () async {
    final repository = _FakeLoginMfaRepository();
    final useCase = CompleteLoginMfaUseCase(
      repository: repository,
      tokenRepository: _FakeTokenRepository(),
      clock: () => _now,
    );

    await useCase.execute(
      challenge: _challenge(),
      method: LoginMfaMethod.recoveryCode,
      code: 'abcde-12345 ',
    );

    expect(repository.calls, ['mfa-token-1|recovery_code|ABCDE-12345']);
  });

  test(
    'wrong code keeps attempts_left for the message, no token saved',
    () async {
      final repository = _FakeLoginMfaRepository(
        next: const FailureResult(
          Failure(
            kind: FailureKind.unauthorized,
            code: 'MFA_INVALID_CODE',
            message: 'Sai mã',
            details: {'attempts_left': 3},
          ),
        ),
      );
      final tokens = _FakeTokenRepository();
      final useCase = CompleteLoginMfaUseCase(
        repository: repository,
        tokenRepository: tokens,
        clock: () => _now,
      );

      final result = await useCase.execute(
        challenge: _challenge(),
        method: LoginMfaMethod.totp,
        code: '000000',
      );

      final failure = result.failureOrNull!;
      expect(loginMfaAttemptsLeft(failure), 3);
      expect(loginMfaFailureMessage(failure), contains('Còn 3 lần thử'));
      expect(loginMfaMustRestart(failure), isFalse);
      expect(tokens.accessToken, isNull);
    },
  );

  test('expired / too many attempts must restart from the password step', () {
    for (final code in const [
      'MFA_CHALLENGE_EXPIRED',
      'MFA_TOO_MANY_ATTEMPTS',
    ]) {
      expect(
        loginMfaMustRestart(
          Failure(kind: FailureKind.unknown, code: code, message: ''),
        ),
        isTrue,
      );
    }
  });

  test('local checks never call the server', () async {
    final repository = _FakeLoginMfaRepository();
    final useCase = CompleteLoginMfaUseCase(
      repository: repository,
      tokenRepository: _FakeTokenRepository(),
      clock: () => _now.add(const Duration(minutes: 6)),
    );

    final expired = await useCase.execute(
      challenge: _challenge(),
      method: LoginMfaMethod.totp,
      code: '123456',
    );
    expect(expired.failureOrNull?.code, 'MFA_CHALLENGE_EXPIRED');

    final freshUseCase = CompleteLoginMfaUseCase(
      repository: repository,
      tokenRepository: _FakeTokenRepository(),
      clock: () => _now,
    );
    final short = await freshUseCase.execute(
      challenge: _challenge(),
      method: LoginMfaMethod.totp,
      code: '12345',
    );
    expect(short.failureOrNull?.code, 'MFA_CODE_FORMAT');

    final notOffered = await freshUseCase.execute(
      challenge: _challenge(methods: const [LoginMfaMethod.totp]),
      method: LoginMfaMethod.recoveryCode,
      code: 'ABCDE-12345',
    );
    expect(notOffered.failureOrNull?.code, 'MFA_METHOD_NOT_AVAILABLE');

    final passkey = await freshUseCase.execute(
      challenge: _challenge(methods: const [LoginMfaMethod.passkey]),
      method: LoginMfaMethod.passkey,
      code: '',
    );
    expect(passkey.failureOrNull?.code, LoginMfaErrorCode.methodUnsupported);

    expect(repository.calls, isEmpty);
  });

  test('a challenge from another server is not sent after switching', () async {
    final repository = _FakeLoginMfaRepository();
    final useCase = CompleteLoginMfaUseCase(
      repository: repository,
      tokenRepository: _FakeTokenRepository(),
      clock: () => _now,
    );

    final result = await useCase.execute(
      challenge: _challenge(scope: 'scope-b'),
      method: LoginMfaMethod.totp,
      code: '123456',
    );

    expect(loginMfaMustRestart(result.failureOrNull!), isTrue);
    expect(repository.calls, isEmpty);
  });

  test('challenge parsing keeps only known methods and caps the lifetime', () {
    final challenge = LoginMfaChallenge.fromDetails(
      {
        'mfa_token': 'tok',
        'methods': ['passkey', 'sms', 'passkey'],
        'expires_in': 999999,
      },
      instanceScopeId: 'scope-a',
      remember: true,
      now: _now,
    )!;

    expect(challenge.methods, [LoginMfaMethod.passkey]);
    expect(challenge.onlyPasskey, isTrue);
    expect(challenge.secondsLeft(_now), 300);
    expect(
      LoginMfaChallenge.fromDetails(
        {
          'mfa_token': '',
          'methods': ['totp'],
        },
        instanceScopeId: 'scope-a',
        remember: true,
        now: _now,
      ),
      isNull,
    );
  });

  group('màn nhập mã', () {
    test('dán mã có dấu cách / gạch / cả câu vẫn lấy đúng 6 số', () {
      expect(extractLoginTotpCode('123 456'), '123456');
      expect(extractLoginTotpCode('123-456'), '123456');
      expect(extractLoginTotpCode(' 12 34 56 '), '123456');
      expect(
        extractLoginTotpCode('Mã của bạn: 482 913. Hết hạn sau 30 giây'),
        '482913',
      );
      expect(extractLoginTotpCode('12a3'), '123');
      expect(extractLoginTotpCode('12345678'), '123456');
      expect(extractLoginTotpCode(''), '');
    });

    test('mã khôi phục viết hoa và tự chèn gạch sau 5 ký tự', () {
      expect(formatRecoveryCodeInput('ab3k9'), 'AB3K9');
      expect(formatRecoveryCodeInput('ab3k9q'), 'AB3K9-Q');
      expect(formatRecoveryCodeInput('ab3k9 q7x2m'), 'AB3K9-Q7X2M');
      expect(formatRecoveryCodeInput('AB3K9-Q7X2M-EXTRA'), 'AB3K9-Q7X2M');
      expect(formatRecoveryCodeInput('--'), '');
    });

    test('chỉ nhắc thời hạn khi còn dưới một phút', () {
      expect(shouldShowLoginMfaCountdown(300), isFalse);
      expect(shouldShowLoginMfaCountdown(60), isFalse);
      expect(shouldShowLoginMfaCountdown(59), isTrue);
      expect(shouldShowLoginMfaCountdown(1), isTrue);
      expect(shouldShowLoginMfaCountdown(0), isFalse);
    });

    test('cách mặc định: ứng dụng xác thực, không có thì mã khôi phục', () {
      expect(
        defaultLoginMfaMethod(
          _challenge(
            methods: const [LoginMfaMethod.recoveryCode, LoginMfaMethod.totp],
          ),
        ),
        LoginMfaMethod.totp,
      );
      expect(
        defaultLoginMfaMethod(
          _challenge(
            methods: const [
              LoginMfaMethod.passkey,
              LoginMfaMethod.recoveryCode,
            ],
          ),
        ),
        LoginMfaMethod.recoveryCode,
      );
      expect(
        defaultLoginMfaMethod(
          _challenge(methods: const [LoginMfaMethod.passkey]),
        ),
        isNull,
      );
    });

    test('danh sách chọn cách theo thứ tự cố định, gồm cả passkey', () {
      expect(
        loginMfaMethodChoices(
          _challenge(
            methods: const [
              LoginMfaMethod.passkey,
              LoginMfaMethod.recoveryCode,
              LoginMfaMethod.totp,
            ],
          ),
        ),
        [
          LoginMfaMethod.totp,
          LoginMfaMethod.recoveryCode,
          LoginMfaMethod.passkey,
        ],
      );
    });
  });
}

final class _FakeLoginMfaRepository implements LoginMfaRepository {
  _FakeLoginMfaRepository({Result<AuthSession>? next})
    : next =
          next ??
          const Success(
            AuthSession(
              tokens: AuthTokens(
                accessToken: 'access-mfa',
                refreshToken: 'refresh-mfa',
              ),
              sessionId: 'session-1',
            ),
          );

  final Result<AuthSession> next;
  final calls = <String>[];

  @override
  Future<Result<AuthSession>> complete({
    required String mfaToken,
    required LoginMfaMethod method,
    required String code,
  }) async {
    calls.add('$mfaToken|${method.apiValue}|$code');
    return next;
  }
}

final class _FakeTokenRepository implements AuthTokenRepository {
  static const guard = AuthTokenMutationGuard(
    instanceScopeId: 'scope-a',
    generation: 'generation-a',
  );

  String? accessToken;
  String? refreshToken;
  AuthTokenPersistence? lastPersistence;

  @override
  Future<AuthTokenMutationGuard?> captureMutationGuard() async => guard;

  @override
  Future<void> clearTokens() async {
    accessToken = null;
    refreshToken = null;
  }

  @override
  Future<bool> clearTokensIfCurrent(AuthTokenMutationGuard value) async =>
      value == guard;

  @override
  Future<bool> isMutationGuardCurrent(AuthTokenMutationGuard value) async =>
      value == guard;

  @override
  Future<String?> readAccessToken() async => accessToken;

  @override
  Future<String?> readAccessTokenIfCurrent(
    AuthTokenMutationGuard value,
  ) async => value == guard ? accessToken : null;

  @override
  Future<String?> readRefreshToken() async => refreshToken;

  @override
  Future<String?> readRefreshTokenIfCurrent(
    AuthTokenMutationGuard value,
  ) async => value == guard ? refreshToken : null;

  @override
  Future<void> saveTokens(AuthTokens tokens) async {
    accessToken = tokens.accessToken;
    refreshToken = tokens.refreshToken;
  }

  @override
  Future<bool> saveTokensIfCurrent(
    AuthTokens tokens,
    AuthTokenMutationGuard value, {
    AuthTokenPersistence? persistence,
  }) async {
    if (value != guard) return false;
    lastPersistence = persistence;
    await saveTokens(tokens);
    return true;
  }
}

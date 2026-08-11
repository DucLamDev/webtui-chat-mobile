import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/error/failure.dart';
import 'package:webtui_chat/core/result/result.dart';
import 'package:webtui_chat/features/auth/application/use_cases/delete_account_use_case.dart';
import 'package:webtui_chat/features/auth/domain/entities/auth_tokens.dart';
import 'package:webtui_chat/features/auth/domain/repositories/account_repository.dart';
import 'package:webtui_chat/features/auth/domain/repositories/app_lock_repository.dart';
import 'package:webtui_chat/features/auth/domain/repositories/auth_token_repository.dart';
import 'package:webtui_chat/features/auth/domain/repositories/session_state_repository.dart';

void main() {
  test('deletes remotely before clearing all account-local state', () async {
    final account = _FakeAccountRepository(const Success(null));
    final session = _FakeSessionStateRepository();
    final appLock = _FakeAppLockRepository();
    final useCase = DeleteAccountUseCase(
      accountRepository: account,
      tokenRepository: _FakeTokenRepository(),
      sessionStateRepository: session,
      appLockRepository: appLock,
    );

    final result = await useCase.execute(
      confirmation: ' delete ',
      ownershipSuccessorEmail: ' successor@example.com ',
    );

    expect(result.isSuccess, isTrue);
    expect(account.confirmation, 'DELETE');
    expect(account.ownershipSuccessorEmail, 'successor@example.com');
    expect(session.resetCalls, 1);
    expect(appLock.disableCalls, 1);
  });

  test('does not clear local state when server deletion fails', () async {
    final account = _FakeAccountRepository(
      const FailureResult(
        Failure(
          kind: FailureKind.network,
          code: 'ACCOUNT_DELETE_FAILED',
          message: 'Không thể xóa.',
        ),
      ),
    );
    final session = _FakeSessionStateRepository();
    final appLock = _FakeAppLockRepository();
    final useCase = DeleteAccountUseCase(
      accountRepository: account,
      tokenRepository: _FakeTokenRepository(),
      sessionStateRepository: session,
      appLockRepository: appLock,
    );

    final result = await useCase.execute();

    expect(result.failureOrNull?.code, 'ACCOUNT_DELETE_FAILED');
    expect(session.resetCalls, 0);
    expect(appLock.disableCalls, 0);
  });

  test('preserves server conflict details for workspace owners', () async {
    const serverMessage =
        'Hãy chọn một thành viên đang hoạt động để nhận quyền sở hữu.';
    final account = _FakeAccountRepository(
      const FailureResult(
        Failure(
          kind: FailureKind.conflict,
          code: 'OWNERSHIP_SUCCESSOR_REQUIRED',
          message: serverMessage,
        ),
      ),
    );
    final useCase = DeleteAccountUseCase(
      accountRepository: account,
      tokenRepository: _FakeTokenRepository(),
      sessionStateRepository: _FakeSessionStateRepository(),
      appLockRepository: _FakeAppLockRepository(),
    );

    final result = await useCase.execute();

    expect(result.failureOrNull?.kind, FailureKind.conflict);
    expect(result.failureOrNull?.message, serverMessage);
  });

  test('rejects an ambiguous destructive confirmation locally', () async {
    final account = _FakeAccountRepository(const Success(null));
    final useCase = DeleteAccountUseCase(
      accountRepository: account,
      tokenRepository: _FakeTokenRepository(),
      sessionStateRepository: _FakeSessionStateRepository(),
      appLockRepository: _FakeAppLockRepository(),
    );

    final result = await useCase.execute(confirmation: 'YES');

    expect(result.failureOrNull?.code, 'ACCOUNT_DELETE_CONFIRMATION_INVALID');
    expect(account.calls, 0);
  });

  test(
    'late A deletion cannot clear server B session, workspace, or PIN',
    () async {
      final deletion = Completer<Result<void>>();
      final account = _FakeAccountRepository(
        const Success(null),
        resultFuture: deletion.future,
      );
      final tokens = _FakeTokenRepository()
        ..accessToken = 'access-a'
        ..refreshToken = 'refresh-a';
      final session = _FakeSessionStateRepository()
        ..workspaceId = 'workspace-a';
      final appLock = _FakeAppLockRepository();
      final useCase = DeleteAccountUseCase(
        accountRepository: account,
        tokenRepository: tokens,
        sessionStateRepository: session,
        appLockRepository: appLock,
      );

      final pending = useCase.execute();
      await Future<void>.delayed(Duration.zero);
      const guardB = AuthTokenMutationGuard(
        instanceScopeId: 'scope-b',
        generation: 'generation-b',
      );
      tokens
        ..currentGuard = guardB
        ..accessToken = 'access-b'
        ..refreshToken = 'refresh-b';
      session
        ..currentGuard = guardB
        ..workspaceId = 'workspace-b'
        ..hasSavedSession = true;
      deletion.complete(const Success(null));

      expect((await pending).isSuccess, isTrue);
      expect(tokens.accessToken, 'access-b');
      expect(tokens.refreshToken, 'refresh-b');
      expect(session.workspaceId, 'workspace-b');
      expect(appLock.disableCalls, 0);
    },
  );
}

final class _FakeAccountRepository implements AccountRepository {
  _FakeAccountRepository(this.result, {this.resultFuture});

  final Result<void> result;
  final Future<Result<void>>? resultFuture;
  int calls = 0;
  String? confirmation;
  String? ownershipSuccessorEmail;

  @override
  Future<Result<void>> deleteAccount({
    required String confirmation,
    String? ownershipSuccessorEmail,
  }) async {
    calls += 1;
    this.confirmation = confirmation;
    this.ownershipSuccessorEmail = ownershipSuccessorEmail;
    return resultFuture ?? result;
  }
}

final class _FakeSessionStateRepository implements SessionStateRepository {
  int resetCalls = 0;
  bool hasSavedSession = false;
  AuthTokenMutationGuard currentGuard = _FakeTokenRepository.defaultGuard;
  String? workspaceId;

  @override
  Future<AuthTokenMutationGuard?> captureActiveSessionGuard() async =>
      currentGuard;

  @override
  Future<bool> hasAnySavedSession() async => hasSavedSession;

  @override
  Future<void> resetForLogout() async {
    resetCalls += 1;
    workspaceId = null;
  }

  @override
  Future<bool> resetForLogoutIfCurrent(AuthTokenMutationGuard guard) async {
    resetCalls += 1;
    if (guard != currentGuard) return false;
    workspaceId = null;
    return true;
  }

  @override
  Future<void> resetForServerSwitch() async {}
}

final class _FakeTokenRepository implements AuthTokenRepository {
  static const defaultGuard = AuthTokenMutationGuard(
    instanceScopeId: 'scope-a',
    generation: 'generation-a',
  );

  AuthTokenMutationGuard currentGuard = defaultGuard;
  String? accessToken;
  String? refreshToken;

  @override
  Future<AuthTokenMutationGuard?> captureMutationGuard() async => currentGuard;

  @override
  Future<void> clearTokens() async {
    accessToken = null;
    refreshToken = null;
  }

  @override
  Future<bool> clearTokensIfCurrent(AuthTokenMutationGuard guard) async =>
      guard == currentGuard;

  @override
  Future<bool> isMutationGuardCurrent(AuthTokenMutationGuard guard) async =>
      guard == currentGuard;

  @override
  Future<String?> readAccessToken() async => accessToken;

  @override
  Future<String?> readAccessTokenIfCurrent(
    AuthTokenMutationGuard guard,
  ) async => guard == currentGuard ? accessToken : null;

  @override
  Future<String?> readRefreshToken() async => refreshToken;

  @override
  Future<String?> readRefreshTokenIfCurrent(
    AuthTokenMutationGuard guard,
  ) async => guard == currentGuard ? refreshToken : null;

  @override
  Future<void> saveTokens(AuthTokens tokens) async {
    accessToken = tokens.accessToken;
    refreshToken = tokens.refreshToken;
  }

  @override
  Future<bool> saveTokensIfCurrent(
    AuthTokens tokens,
    AuthTokenMutationGuard guard, {
    AuthTokenPersistence? persistence,
  }) async {
    if (guard != currentGuard) return false;
    await saveTokens(tokens);
    return true;
  }
}

final class _FakeAppLockRepository implements AppLockRepository {
  int disableCalls = 0;

  @override
  Future<void> disable() async {
    disableCalls += 1;
  }

  @override
  Future<void> enablePin(String pin) async {}

  @override
  Future<bool> isEnabled() async => true;

  @override
  Future<bool> verifyPin(String pin) async => true;
}

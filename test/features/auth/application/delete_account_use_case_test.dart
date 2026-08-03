import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/error/failure.dart';
import 'package:webtui_chat/core/result/result.dart';
import 'package:webtui_chat/features/auth/application/use_cases/delete_account_use_case.dart';
import 'package:webtui_chat/features/auth/domain/repositories/account_repository.dart';
import 'package:webtui_chat/features/auth/domain/repositories/app_lock_repository.dart';
import 'package:webtui_chat/features/auth/domain/repositories/session_state_repository.dart';

void main() {
  test('deletes remotely before clearing all account-local state', () async {
    final account = _FakeAccountRepository(const Success(null));
    final session = _FakeSessionStateRepository();
    final appLock = _FakeAppLockRepository();
    final useCase = DeleteAccountUseCase(
      accountRepository: account,
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
      sessionStateRepository: _FakeSessionStateRepository(),
      appLockRepository: _FakeAppLockRepository(),
    );

    final result = await useCase.execute(confirmation: 'YES');

    expect(result.failureOrNull?.code, 'ACCOUNT_DELETE_CONFIRMATION_INVALID');
    expect(account.calls, 0);
  });
}

final class _FakeAccountRepository implements AccountRepository {
  _FakeAccountRepository(this.result);

  final Result<void> result;
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
    return result;
  }
}

final class _FakeSessionStateRepository implements SessionStateRepository {
  int resetCalls = 0;

  @override
  Future<void> resetForLogout() async {
    resetCalls += 1;
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

import '../../../../core/error/failure.dart';
import '../../../../core/result/result.dart';
import '../../domain/repositories/account_repository.dart';
import '../../domain/repositories/app_lock_repository.dart';
import '../../domain/repositories/session_state_repository.dart';

final class DeleteAccountUseCase {
  const DeleteAccountUseCase({
    required AccountRepository accountRepository,
    required SessionStateRepository sessionStateRepository,
    required AppLockRepository appLockRepository,
  }) : _accountRepository = accountRepository,
       _sessionStateRepository = sessionStateRepository,
       _appLockRepository = appLockRepository;

  final AccountRepository _accountRepository;
  final SessionStateRepository _sessionStateRepository;
  final AppLockRepository _appLockRepository;

  Future<Result<void>> execute({
    String confirmation = 'DELETE',
    String? ownershipSuccessorEmail,
  }) async {
    final normalizedConfirmation = confirmation.trim().toUpperCase();
    if (normalizedConfirmation != 'DELETE') {
      return const FailureResult(
        Failure(
          kind: FailureKind.validation,
          code: 'ACCOUNT_DELETE_CONFIRMATION_INVALID',
          message: 'Nhập DELETE để xác nhận xóa tài khoản.',
        ),
      );
    }

    final deletion = await _accountRepository.deleteAccount(
      confirmation: normalizedConfirmation,
      ownershipSuccessorEmail: ownershipSuccessorEmail?.trim(),
    );
    if (deletion case FailureResult<void>()) {
      return deletion;
    }

    Object? cleanupError;
    try {
      await _sessionStateRepository.resetForLogout();
    } on Object catch (error) {
      cleanupError = error;
    }
    try {
      await _appLockRepository.disable();
    } on Object catch (error) {
      cleanupError ??= error;
    }
    if (cleanupError != null) {
      return FailureResult(
        Failure(
          kind: FailureKind.storage,
          code: 'ACCOUNT_DELETED_LOCAL_CLEAR_FAILED',
          message:
              'Tài khoản đã được xóa nhưng chưa dọn hết dữ liệu trên thiết bị. Hãy xóa dữ liệu ứng dụng trước khi đăng nhập lại.',
          cause: cleanupError,
        ),
      );
    }
    return const Success(null);
  }
}

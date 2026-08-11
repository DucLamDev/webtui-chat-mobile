import '../../../../core/error/failure.dart';
import '../../../../core/result/result.dart';
import '../../domain/repositories/account_repository.dart';
import '../../domain/repositories/app_lock_repository.dart';
import '../../domain/repositories/auth_token_repository.dart';
import '../../domain/repositories/session_state_repository.dart';

final class DeleteAccountUseCase {
  const DeleteAccountUseCase({
    required AccountRepository accountRepository,
    required AuthTokenRepository tokenRepository,
    required SessionStateRepository sessionStateRepository,
    required AppLockRepository appLockRepository,
  }) : _accountRepository = accountRepository,
       _tokenRepository = tokenRepository,
       _sessionStateRepository = sessionStateRepository,
       _appLockRepository = appLockRepository;

  final AccountRepository _accountRepository;
  final AuthTokenRepository _tokenRepository;
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

    final guard = await _tokenRepository.captureMutationGuard();
    if (guard == null ||
        !await _tokenRepository.isMutationGuardCurrent(guard)) {
      return const FailureResult(
        Failure(
          kind: FailureKind.unauthorized,
          code: 'AUTH_INSTANCE_CHANGED',
          message: 'Máy chủ đang hoạt động đã thay đổi.',
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
    var clearedActiveSession = false;
    try {
      clearedActiveSession = await _sessionStateRepository
          .resetForLogoutIfCurrent(guard);
    } on Object catch (error) {
      cleanupError = error;
    }
    try {
      if (clearedActiveSession &&
          !await _sessionStateRepository.hasAnySavedSession()) {
        await _appLockRepository.disable();
      }
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

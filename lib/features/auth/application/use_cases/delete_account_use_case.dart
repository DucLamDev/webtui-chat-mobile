import '../../../../core/error/failure.dart';
import '../../../../core/result/result.dart';
import '../../../../l10n/app_strings.dart';
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
    Future<void> Function()? purgeDeviceKeys,
  }) : _accountRepository = accountRepository,
       _tokenRepository = tokenRepository,
       _sessionStateRepository = sessionStateRepository,
       _appLockRepository = appLockRepository,
       _purgeDeviceKeys = purgeDeviceKeys;

  final AccountRepository _accountRepository;
  final AuthTokenRepository _tokenRepository;
  final SessionStateRepository _sessionStateRepository;
  final AppLockRepository _appLockRepository;

  /// Xoá khoá thiết bị của tài khoản khỏi máy (lỗi bỏ qua: bản ghi còn đó, lần
  /// đăng nhập của người khác sẽ xoá tiếp).
  final Future<void> Function()? _purgeDeviceKeys;

  /// [reauthToken]: token xác thực lại vừa lấy trên thiết bị này (không lưu,
  /// không dùng lại). Thiếu thì không gọi máy chủ.
  Future<Result<void>> execute({
    String confirmation = 'DELETE',
    String? ownershipSuccessorEmail,
    required String? reauthToken,
  }) async {
    final normalizedConfirmation = confirmation.trim().toUpperCase();
    if (normalizedConfirmation != 'DELETE') {
      return FailureResult(
        Failure(
          kind: FailureKind.validation,
          code: 'ACCOUNT_DELETE_CONFIRMATION_INVALID',
          message: tr(
            'Nhập DELETE để xác nhận xóa tài khoản.',
            'Type DELETE to confirm deleting your account.',
          ),
        ),
      );
    }

    final token = reauthToken?.trim() ?? '';
    if (token.isEmpty) {
      return FailureResult(
        Failure(
          kind: FailureKind.forbidden,
          code: 'REAUTH_REQUIRED',
          message: tr(
            'Cần xác thực lại trước khi xóa tài khoản.',
            'Verify again before deleting your account.',
          ),
        ),
      );
    }

    final guard = await _tokenRepository.captureMutationGuard();
    if (guard == null ||
        !await _tokenRepository.isMutationGuardCurrent(guard)) {
      return FailureResult(
        Failure(
          kind: FailureKind.unauthorized,
          code: 'AUTH_INSTANCE_CHANGED',
          message: tr(
            'Máy chủ đang hoạt động đã thay đổi.',
            'The active server has changed.',
          ),
        ),
      );
    }

    final deletion = await _accountRepository.deleteAccount(
      confirmation: normalizedConfirmation,
      reauthToken: token,
      ownershipSuccessorEmail: ownershipSuccessorEmail?.trim(),
    );
    if (deletion case FailureResult<void>()) {
      return deletion;
    }

    try {
      await _purgeDeviceKeys?.call();
    } on Object {
      // Không cản việc dọn phiên.
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
          message: tr(
            'Tài khoản đã được xóa nhưng chưa dọn hết dữ liệu trên thiết bị. Hãy xóa dữ liệu ứng dụng trước khi đăng nhập lại.',
            'Your account was deleted, but some data on this device was not cleared. Clear the app data before signing in again.',
          ),
          cause: cleanupError,
        ),
      );
    }
    return const Success(null);
  }
}

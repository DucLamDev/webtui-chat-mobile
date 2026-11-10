import '../../../../core/error/failure.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/app_lock_timeout_policy.dart';
import '../../domain/repositories/app_lock_timeout_repository.dart';

final class LoadAppLockIdleMinutesUseCase {
  const LoadAppLockIdleMinutesUseCase(this._repository);

  final AppLockTimeoutRepository _repository;

  Future<int?> execute() => _repository.readIdleMinutes();
}

final class SaveAppLockIdleMinutesUseCase {
  const SaveAppLockIdleMinutesUseCase(this._repository);

  final AppLockTimeoutRepository _repository;

  /// Lưu mức tự khoá; không cho chọn dài hơn mức máy chủ cho phép.
  Future<Result<void>> execute({
    required int minutes,
    required int serverMaxMinutes,
  }) async {
    if (minutes <= 0) {
      return const FailureResult(
        Failure(
          kind: FailureKind.validation,
          message: 'Thời gian tự khóa phải lớn hơn 0 phút.',
          code: 'APP_LOCK_TIMEOUT_INVALID',
        ),
      );
    }
    if (serverMaxMinutes > 0 && minutes > serverMaxMinutes) {
      return FailureResult(
        Failure(
          kind: FailureKind.validation,
          message:
              'Máy chủ chỉ cho phép tự khóa sau tối đa '
              '${AppLockTimeoutPolicy.label(serverMaxMinutes)}.',
          code: 'APP_LOCK_TIMEOUT_TOO_LONG',
        ),
      );
    }
    await _repository.writeIdleMinutes(minutes);
    return const Success(null);
  }
}

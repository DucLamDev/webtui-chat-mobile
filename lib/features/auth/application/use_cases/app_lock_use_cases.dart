import '../../../../core/error/failure.dart';
import '../../../../core/result/result.dart';
import '../../domain/repositories/app_lock_repository.dart';

final class IsAppLockEnabledUseCase {
  const IsAppLockEnabledUseCase(this._repository);

  final AppLockRepository _repository;

  Future<bool> execute() {
    return _repository.isEnabled();
  }
}

final class EnableAppLockUseCase {
  const EnableAppLockUseCase(this._repository);

  final AppLockRepository _repository;

  Future<Result<void>> execute(String pin) async {
    if (!RegExp(r'^\d{4,12}$').hasMatch(pin)) {
      return const FailureResult(
        Failure(
          kind: FailureKind.validation,
          message: 'Mã PIN cần gồm 4-12 chữ số.',
          code: 'APP_LOCK_PIN_INVALID',
        ),
      );
    }

    await _repository.enablePin(pin);
    return const Success(null);
  }
}

final class UnlockAppUseCase {
  const UnlockAppUseCase(this._repository);

  final AppLockRepository _repository;

  Future<Result<void>> execute(String pin) async {
    final ok = await _repository.verifyPin(pin);
    if (!ok) {
      return const FailureResult(
        Failure(
          kind: FailureKind.unauthorized,
          message: 'Mã PIN không đúng.',
          code: 'APP_LOCK_PIN_MISMATCH',
        ),
      );
    }
    return const Success(null);
  }
}

final class DisableAppLockUseCase {
  const DisableAppLockUseCase(this._repository);

  final AppLockRepository _repository;

  Future<void> execute() {
    return _repository.disable();
  }
}

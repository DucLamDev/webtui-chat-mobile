import '../../../../core/security/secure_key_value_store.dart';
import '../../domain/repositories/app_lock_timeout_repository.dart';

final class SecureAppLockTimeoutRepository implements AppLockTimeoutRepository {
  const SecureAppLockTimeoutRepository(this._store);

  final SecureKeyValueStore _store;

  @override
  Future<int?> readIdleMinutes() async {
    final raw = await _store.read(SecureStoreKey.appLockIdleMinutes);
    final value = int.tryParse(raw?.trim() ?? '');
    return value != null && value > 0 ? value : null;
  }

  @override
  Future<void> writeIdleMinutes(int minutes) {
    return _store.write(SecureStoreKey.appLockIdleMinutes, minutes.toString());
  }
}

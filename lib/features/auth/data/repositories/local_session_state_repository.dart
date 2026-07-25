import '../../../../core/database/app_database.dart';
import '../../../../core/security/secure_key_value_store.dart';
import '../../domain/repositories/session_state_repository.dart';

final class LocalSessionStateRepository implements SessionStateRepository {
  const LocalSessionStateRepository({
    required SecureKeyValueStore secureStore,
    required AppDatabase database,
  }) : _secureStore = secureStore,
       _database = database;

  final SecureKeyValueStore _secureStore;
  final AppDatabase _database;

  @override
  Future<void> resetForLogout() async {
    await _secureStore.clearSession();
    await Future.wait([
      _database.deleteScopesWithPrefix('workspace:'),
      _database.deleteScope('session'),
    ]);
  }
}

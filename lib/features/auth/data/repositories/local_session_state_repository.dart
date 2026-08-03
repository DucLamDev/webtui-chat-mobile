import '../../../../core/database/app_database.dart';
import '../../../../core/security/secure_key_value_store.dart';
import '../../../../core/security/server_account_registry.dart';
import '../../domain/repositories/session_state_repository.dart';

final class LocalSessionStateRepository implements SessionStateRepository {
  const LocalSessionStateRepository({
    required SecureKeyValueStore secureStore,
    required AppDatabase database,
    SecureServerAccountRegistry? serverAccountRegistry,
  }) : _secureStore = secureStore,
       _database = database,
       _serverAccountRegistry = serverAccountRegistry;

  final SecureKeyValueStore _secureStore;
  final AppDatabase _database;
  final SecureServerAccountRegistry? _serverAccountRegistry;

  @override
  Future<void> resetForLogout() async {
    await _serverAccountRegistry?.clearActiveSession();
    await _secureStore.clearSession();
    await Future.wait([
      _database.deleteScopesWithPrefix('workspace:'),
      _database.deleteScope('session'),
    ]);
  }
}

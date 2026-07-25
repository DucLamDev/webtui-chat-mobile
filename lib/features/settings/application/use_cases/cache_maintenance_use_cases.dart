import '../../../../core/database/app_database.dart';

final class ClearWorkspaceCacheUseCase {
  const ClearWorkspaceCacheUseCase(this._database);

  final AppDatabase _database;

  Future<void> execute({required String workspaceId}) async {
    final normalized = workspaceId.trim();
    if (normalized.isEmpty) {
      return;
    }
    await _database.deleteScope('conversation_cache:$normalized');
    await _database.deleteScopesWithPrefix('message_cache:$normalized:');
  }
}

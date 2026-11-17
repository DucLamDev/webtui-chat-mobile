import '../../../../core/database/app_database.dart';
import '../../../../core/security/instance_scope.dart';
import '../../domain/entities/conversation_list_prefs.dart';
import '../../domain/repositories/conversation_list_prefs_repository.dart';

/// Lưu ghim / chưa đọc / ẩn của danh sách chat vào cơ sở dữ liệu trên máy,
/// tách theo máy chủ (phạm vi instance), tài khoản và không gian làm việc.
final class LocalConversationListPrefsRepository
    implements ConversationListPrefsRepository {
  const LocalConversationListPrefsRepository(
    this._database,
    this._instanceScope,
  );

  final AppDatabase _database;
  final InstanceScope _instanceScope;

  String get _scope => _instanceScope.localScope('conversation_list_prefs');

  @override
  Future<ConversationListPrefs> read({
    required String userId,
    required String workspaceId,
  }) async {
    final raw = await _database.readKeyValue(
      scope: _scope,
      key: _key(userId, workspaceId),
    );
    return ConversationListPrefs.decode(raw);
  }

  @override
  Future<void> save({
    required String userId,
    required String workspaceId,
    required ConversationListPrefs prefs,
  }) {
    final key = _key(userId, workspaceId);
    if (prefs.isEmpty) {
      return _database.deleteKeyValue(scope: _scope, key: key);
    }
    return _database.putKeyValue(
      scope: _scope,
      key: key,
      value: prefs.encode(),
    );
  }
}

String _key(String userId, String workspaceId) => '$userId:$workspaceId';

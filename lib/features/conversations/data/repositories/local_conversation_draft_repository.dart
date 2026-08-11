import '../../../../core/database/app_database.dart';
import '../../../../core/security/instance_scope.dart';
import '../../domain/repositories/conversation_repository.dart';

final class LocalConversationDraftRepository
    implements ConversationDraftRepository {
  const LocalConversationDraftRepository(this._database, this._instanceScope);

  final AppDatabase _database;
  final InstanceScope _instanceScope;

  String get _scope => _instanceScope.localScope('conversation_drafts');

  @override
  Future<String> readDraft({
    required String workspaceId,
    required String channelId,
  }) async {
    return await _database.readKeyValue(
          scope: _scope,
          key: _key(workspaceId, channelId),
        ) ??
        '';
  }

  @override
  Future<void> saveDraft({
    required String workspaceId,
    required String channelId,
    required String body,
  }) {
    return _database.putKeyValue(
      scope: _scope,
      key: _key(workspaceId, channelId),
      value: body,
    );
  }

  @override
  Future<void> clearDraft({
    required String workspaceId,
    required String channelId,
  }) {
    return _database.deleteKeyValue(
      scope: _scope,
      key: _key(workspaceId, channelId),
    );
  }
}

String _key(String workspaceId, String channelId) => '$workspaceId:$channelId';

import '../entities/conversation_list_prefs.dart';

/// Nơi lưu [ConversationListPrefs] trên máy, theo tài khoản + không gian.
abstract interface class ConversationListPrefsRepository {
  Future<ConversationListPrefs> read({
    required String userId,
    required String workspaceId,
  });

  Future<void> save({
    required String userId,
    required String workspaceId,
    required ConversationListPrefs prefs,
  });
}

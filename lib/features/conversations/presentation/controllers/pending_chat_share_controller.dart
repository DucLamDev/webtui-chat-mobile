import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/platform/chat_share_intent_service.dart';

final pendingChatShareProvider =
    StateNotifierProvider<PendingChatShares, Map<String, ChatSharePayload>>(
      (_) => PendingChatShares(),
    );

final class PendingChatShares
    extends StateNotifier<Map<String, ChatSharePayload>> {
  PendingChatShares() : super(const {});

  void put({
    required String workspaceId,
    required String channelId,
    required ChatSharePayload payload,
  }) {
    state = {
      ...state,
      _key(workspaceId: workspaceId, channelId: channelId): payload,
    };
  }

  ChatSharePayload? take({
    required String workspaceId,
    required String channelId,
  }) {
    final key = _key(workspaceId: workspaceId, channelId: channelId);
    final payload = state[key];
    if (payload == null) {
      return null;
    }
    final next = Map<String, ChatSharePayload>.of(state)..remove(key);
    state = next;
    return payload;
  }
}

String _key({required String workspaceId, required String channelId}) {
  return '${workspaceId.trim()}::${channelId.trim()}';
}

import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/conversations/domain/entities/conversation_summary.dart';

void main() {
  group('ConversationSummary directCallTargetUserId', () {
    test('uses direct peer user id', () {
      final conversation = _conversation(peerUserId: 'user-2');

      expect(
        conversation.directCallTargetUserId(currentUserId: 'user-1'),
        'user-2',
      );
    });

    test('falls back to the other participant', () {
      final conversation = _conversation(
        participantIds: const ['user-1', 'user-2'],
      );

      expect(
        conversation.directCallTargetUserId(currentUserId: 'user-1'),
        'user-2',
      );
    });

    test('does not return a call target for channels', () {
      final channel = _conversation(
        kind: ConversationKind.channel,
        peerUserId: 'user-2',
      );

      expect(channel.directCallTargetUserId(currentUserId: 'user-1'), isNull);
    });

    test('does not guess from multiple participants without current user', () {
      final conversation = _conversation(
        participantIds: const ['user-1', 'user-2'],
      );

      expect(conversation.directCallTargetUserId(), isNull);
    });
  });
}

ConversationSummary _conversation({
  ConversationKind kind = ConversationKind.direct,
  String? peerUserId,
  List<String> participantIds = const [],
}) {
  return ConversationSummary(
    id: 'conversation-1',
    workspaceId: 'workspace-1',
    channelId: 'channel-1',
    kind: kind,
    title: 'Lam Duc',
    preview: '',
    updatedAt: DateTime.utc(2026),
    peerUserId: peerUserId,
    participantIds: participantIds,
  );
}

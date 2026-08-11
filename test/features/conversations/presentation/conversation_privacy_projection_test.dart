import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/conversations/domain/entities/conversation_summary.dart';
import 'package:webtui_chat/features/conversations/presentation/models/conversation_privacy_projection.dart';
import 'package:webtui_chat/features/conversations/presentation/screens/workspace_tools_screen.dart';
import 'package:webtui_chat/features/moderation/domain/entities/moderation.dart';
import 'package:webtui_chat/features/moderation/presentation/controllers/moderation_controller.dart';

void main() {
  test('blocked direct peer message preview is replaced', () {
    final conversation = _conversation(
      peerUserId: 'blocked-user',
      preview: 'Sensitive last message',
    );

    final projection = ConversationPrivacyProjection.from(conversation, const {
      'blocked-user',
    });

    expect(projection.isBlocked, isTrue);
    expect(projection.blockedPeerUserId, 'blocked-user');
    expect(projection.preview, blockedConversationPreview);
    expect(projection.preview, isNot(contains('Sensitive')));
  });

  test('blocked participant is detected when older payload omits peer id', () {
    final conversation = _conversation(
      participantIds: const ['current-user', 'blocked-user'],
    );

    expect(
      blockedDirectPeerUserId(conversation, const {'blocked-user'}),
      'blocked-user',
    );
  });

  test('channel preview is not masked by direct-user block policy', () {
    final conversation = _conversation(
      kind: ConversationKind.channel,
      participantIds: const ['blocked-user'],
      preview: 'Channel announcement',
    );

    final projection = ConversationPrivacyProjection.from(conversation, const {
      'blocked-user',
    });

    expect(projection.isBlocked, isFalse);
    expect(projection.preview, 'Channel announcement');
  });

  test('search cannot reveal a blocked raw last-message preview', () {
    final conversation = _conversation(
      peerUserId: 'blocked-user',
      preview: 'confidential acquisition',
    );

    final results = privacySafeConversationResults(
      [conversation],
      const {'blocked-user'},
      searchQuery: 'acquisition',
    );

    expect(results, isEmpty);
  });

  test('shared-content tools are disabled for a blocked direct peer', () {
    final conversation = _conversation(peerUserId: 'blocked-user');
    final state = ModerationState(
      blockedUsers: [
        BlockedUser(
          blockedUserId: 'blocked-user',
          createdAt: DateTime.utc(2026, 8, 7),
        ),
      ],
    );

    expect(workspaceToolsSharedContentBlocked(conversation, state), isTrue);
  });

  test(
    'direct shared-content tools fail closed until block policy is ready',
    () {
      final conversation = _conversation(peerUserId: 'peer-user');

      expect(
        workspaceToolsSharedContentBlocked(
          conversation,
          const ModerationState(isLoadingBlockedUsers: true),
        ),
        isTrue,
      );
      expect(
        workspaceToolsSharedContentBlocked(
          conversation,
          const ModerationState(errorMessage: 'Safety lookup failed.'),
        ),
        isTrue,
      );
    },
  );

  test('channel shared-content tools remain available after a user block', () {
    final channel = _conversation(kind: ConversationKind.channel);
    final state = ModerationState(
      blockedUsers: [
        BlockedUser(
          blockedUserId: 'blocked-user',
          createdAt: DateTime.utc(2026, 8, 7),
        ),
      ],
    );

    expect(workspaceToolsSharedContentBlocked(channel, state), isFalse);
  });
}

ConversationSummary _conversation({
  ConversationKind kind = ConversationKind.direct,
  String preview = 'Last message',
  String? peerUserId,
  List<String> participantIds = const [],
}) {
  return ConversationSummary(
    id: 'conversation-1',
    workspaceId: 'workspace-1',
    channelId: 'channel-1',
    kind: kind,
    title: 'Conversation title',
    preview: preview,
    updatedAt: DateTime.utc(2026, 8, 7),
    peerUserId: peerUserId,
    participantIds: participantIds,
  );
}

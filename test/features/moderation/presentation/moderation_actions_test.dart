import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/app/providers/foundation_providers.dart';
import 'package:webtui_chat/core/result/result.dart';
import 'package:webtui_chat/features/conversations/domain/entities/chat_message.dart';
import 'package:webtui_chat/features/conversations/presentation/screens/chat_room_screen.dart';
import 'package:webtui_chat/features/moderation/domain/entities/moderation.dart';
import 'package:webtui_chat/features/moderation/domain/repositories/moderation_repository.dart';
import 'package:webtui_chat/features/moderation/presentation/widgets/moderation_actions.dart';

void main() {
  test('senderless bot and integration messages remain reportable', () {
    final message = ChatMessage(
      id: 'integration-message-1',
      workspaceId: 'workspace-1',
      channelId: 'channel-1',
      kind: 'event',
      body: 'External integration content',
      createdAt: DateTime.utc(2026, 8, 7),
    );

    expect(message.senderId, isNull);
    expect(message.isSystem, isFalse);
    expect(shouldOfferMessageReport(message), isTrue);
    expect(shouldOfferMessageReport(message.copyWith(isMine: true)), isFalse);

    final systemMessage = ChatMessage(
      id: 'system-message-1',
      workspaceId: 'workspace-1',
      channelId: 'channel-1',
      kind: 'system',
      body: 'Internal lifecycle event',
      createdAt: DateTime.utc(2026, 8, 7),
    );
    expect(systemMessage.isSystem, isTrue);
  });

  testWidgets('report dialog sends a selected reason and shows confirmation', (
    tester,
  ) async {
    final repository = _FakeModerationRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [moderationRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => FilledButton(
                onPressed: () => reportMessage(
                  context,
                  ref,
                  workspaceId: 'workspace-1',
                  messageId: 'message-1',
                ),
                child: const Text('Báo cáo'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Báo cáo'));
    await tester.pumpAndSettle();

    expect(find.text('Báo cáo tin nhắn'), findsOneWidget);
    expect(find.text('Spam hoặc lừa đảo'), findsOneWidget);

    await tester.tap(find.text('Gửi báo cáo'));
    await tester.pumpAndSettle();

    expect(repository.reportCalls, 1);
    expect(repository.lastTargetId, 'message-1');
    expect(repository.lastReason, ModerationReportReason.spam);
    expect(
      find.text('Đã gửi báo cáo. Cảm ơn bạn đã giúp cộng đồng an toàn.'),
      findsOneWidget,
    );
  });
}

final class _FakeModerationRepository implements ModerationRepository {
  int reportCalls = 0;
  String? lastTargetId;
  ModerationReportReason? lastReason;

  @override
  Future<Result<ModerationReport>> createReport({
    required String workspaceId,
    required ModerationTargetType targetType,
    required String targetId,
    required ModerationReportReason reason,
    String? details,
  }) async {
    reportCalls += 1;
    lastTargetId = targetId;
    lastReason = reason;
    return Success(
      ModerationReport(
        id: 'report-1',
        workspaceId: workspaceId,
        targetType: targetType,
        targetId: targetId,
        reason: reason,
        status: 'pending',
        createdAt: DateTime.utc(2026, 8, 7),
      ),
    );
  }

  @override
  Future<Result<List<BlockedUser>>> listBlockedUsers({
    required String workspaceId,
  }) async => const Success([]);

  @override
  Future<Result<BlockedUser>> blockUser({
    required String workspaceId,
    required String blockedUserId,
    String? reason,
  }) => throw UnimplementedError();

  @override
  Future<Result<void>> unblockUser({
    required String workspaceId,
    required String blockedUserId,
  }) => throw UnimplementedError();
}

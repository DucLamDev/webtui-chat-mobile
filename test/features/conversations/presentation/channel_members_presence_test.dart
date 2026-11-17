import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/design_system/components/webtui_components.dart';
import 'package:webtui_chat/features/conversations/domain/entities/chat_message.dart';
import 'package:webtui_chat/features/conversations/domain/entities/conversation_summary.dart';
import 'package:webtui_chat/features/conversations/presentation/controllers/channel_detail_controller.dart';
import 'package:webtui_chat/features/conversations/presentation/screens/channel_detail_screen.dart';

/// Lỗi 17/11: Bùi Tú Thiên ở danh sách hội thoại không có chấm (offline) nhưng
/// trong chi tiết nhóm lại có chấm xanh — tab Thành viên vẽ chấm theo trạng
/// thái thành viên nhóm (`active` = còn trong nhóm), không theo hiện diện.
void main() {
  ChannelMember member(String userId, String name) => ChannelMember(
    channelId: 'group-1',
    userId: userId,
    email: '$userId@vpsttt.com',
    username: userId,
    displayName: name,
    status: 'active',
    joinedAt: DateTime.utc(2026, 11, 1),
  );

  Future<void> pumpMembers(
    WidgetTester tester,
    Map<String, ConversationPresence> presence,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ChannelMembersTab(
              state: ChannelDetailState(
                scope: const ChannelDetailScope(
                  workspaceId: 'ws',
                  channelId: 'group-1',
                  initialTitle: 'Nhóm',
                ),
                members: [
                  member('thien', 'Bùi Tú Thiên'),
                  member('lam', 'Hồ Đức Lâm'),
                ],
              ),
              inviteController: controller,
              onInvite: () {},
              onApprove: (_) {},
              onReject: (_) {},
              currentUserId: 'lam',
              blockedUserIds: const {},
              presenceByUserId: presence,
              onSafety: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  WebTuiPresenceStatus? statusOf(WidgetTester tester, String name) {
    return tester
        .widget<WebTuiConversationListItem>(
          find.ancestor(
            of: find.text(name),
            matching: find.byType(WebTuiConversationListItem),
          ),
        )
        .status;
  }

  testWidgets(
    'thành viên còn trong nhóm nhưng offline thì không có chấm xanh',
    (tester) async {
      await pumpMembers(tester, const {
        'thien': ConversationPresence.offline,
        'lam': ConversationPresence.online,
      });

      expect(statusOf(tester, 'Bùi Tú Thiên'), isNull);
      expect(statusOf(tester, 'Hồ Đức Lâm'), WebTuiPresenceStatus.online);
    },
  );

  testWidgets('chưa tải được hiện diện thì không vẽ chấm cho ai', (
    tester,
  ) async {
    await pumpMembers(tester, const {});

    expect(statusOf(tester, 'Bùi Tú Thiên'), isNull);
    expect(statusOf(tester, 'Hồ Đức Lâm'), isNull);
  });
}

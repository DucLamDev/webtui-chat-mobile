import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:webtui_chat/features/conversations/domain/entities/conversation_summary.dart';
import 'package:webtui_chat/features/conversations/presentation/screens/chat_room_screen.dart';
import 'package:webtui_chat/features/customer_tickets/application/customer_ticket_access_policy.dart';
import 'package:webtui_chat/features/customer_tickets/presentation/controllers/customer_ticket_access_provider.dart';
import 'package:webtui_chat/features/moderation/presentation/controllers/moderation_controller.dart';

void main() {
  // Phiên riêng của kênh Ticket như máy chủ trả: phòng 1-1, không slug, không
  // người nhận, không cờ bot.
  final ticketSession = ConversationSummary(
    id: 'phien-ticket',
    workspaceId: 'ws-1',
    channelId: 'phien-ticket',
    kind: ConversationKind.direct,
    title: 'Ticket',
    preview: '',
    updatedAt: DateTime(2026, 11, 14),
  );

  Future<void> pumpRoom(
    WidgetTester tester, {
    required CustomerTicketAccess access,
  }) async {
    final router = GoRouter(
      initialLocation: '/conversations/phien-ticket',
      routes: [
        GoRoute(
          path: '/conversations/:channelId',
          builder: (_, _) => ChatRoomScreen(
            workspaceId: 'ws-1',
            channelId: 'phien-ticket',
            title: 'Ticket',
            conversation: ticketSession,
          ),
        ),
        GoRoute(
          path: '/customer-tickets',
          builder: (_, state) => Text(
            'hop-thu-ticket ${state.uri.queryParameters['workspaceId']}',
            textDirection: TextDirection.ltr,
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          customerTicketAccessProvider.overrideWith((ref) => access),
          moderationControllerProvider('ws-1').overrideWith(
            (ref) => ModerationController.forTesting(
              workspaceId: 'ws-1',
              initialState: const ModerationState(isLoadingBlockedUsers: true),
            ),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets(
    'mở phiên Ticket (thông báo, liên kết): chuyển sang hộp thư ticket',
    (tester) async {
      await pumpRoom(
        tester,
        access: const CustomerTicketAccess(
          serverSupported: true,
          permissionsLoaded: true,
          canView: true,
          canReply: true,
        ),
      );

      expect(find.text('hop-thu-ticket ws-1'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    },
  );

  testWidgets('không xem được ticket: vẫn mở phòng chat như thường', (
    tester,
  ) async {
    await pumpRoom(tester, access: const CustomerTicketAccess.unavailable());

    expect(find.textContaining('hop-thu-ticket'), findsNothing);
    expect(
      find.byKey(const Key('chat_moderation_loading_gate')),
      findsOneWidget,
    );
  });
}

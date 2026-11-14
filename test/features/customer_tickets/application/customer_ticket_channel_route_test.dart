import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/conversations/domain/entities/conversation_summary.dart';
import 'package:webtui_chat/features/customer_tickets/application/customer_ticket_access_policy.dart';
import 'package:webtui_chat/features/customer_tickets/application/customer_ticket_channel_route.dart';

void main() {
  const canView = CustomerTicketAccess(
    serverSupported: true,
    permissionsLoaded: true,
    canView: true,
    canReply: true,
  );

  ConversationSummary channel({
    String title = 'Ticket',
    String? slug = 'ticket',
    bool automation = true,
    ConversationKind kind = ConversationKind.channel,
    bool privateSession = false,
    String? peerUserId,
  }) {
    return ConversationSummary(
      id: 'c1',
      workspaceId: 'ws-1',
      channelId: 'kenh-ticket',
      kind: kind,
      title: title,
      preview: '',
      updatedAt: DateTime(2026, 11, 12),
      isAutomation: automation,
      privateSessionMode: privateSession,
      peerUserId: peerUserId,
      slug: slug,
    );
  }

  group('customerTicketLocationForConversation', () {
    test('kênh bot Ticket + xem được ticket: mở hộp thư ticket khách', () {
      final location = customerTicketLocationForConversation(
        channel(),
        canView,
      );

      final uri = Uri.parse(location!);
      expect(uri.path, '/customer-tickets');
      expect(uri.queryParameters, {'workspaceId': 'ws-1'});
    });

    test('máy chủ cũ không trả slug: nhận ra kênh bot theo tên "Ticket"', () {
      expect(
        customerTicketLocationForConversation(channel(slug: null), canView),
        isNotNull,
      );
    });

    test('có slug ticket thì không cần cờ bot', () {
      expect(
        customerTicketLocationForConversation(
          channel(automation: false),
          canView,
        ),
        isNotNull,
      );
    });

    test(
      'phiên riêng của kênh Ticket (phòng 1-1 không slug, không người nhận): mở hộp thư ticket',
      () {
        expect(
          customerTicketLocationForConversation(
            channel(
              slug: null,
              automation: false,
              kind: ConversationKind.direct,
            ),
            canView,
          ),
          isNotNull,
        );
        expect(
          customerTicketLocationForConversation(
            channel(slug: null, automation: false, privateSession: true),
            canView,
          ),
          isNotNull,
        );
      },
    );

    test(
      'không xem được ticket (thiếu quyền / máy chủ không hỗ trợ / quyền chưa tải): mở phòng chat',
      () {
        expect(
          customerTicketLocationForConversation(
            channel(),
            const CustomerTicketAccess.unavailable(),
          ),
          isNull,
        );
        expect(
          customerTicketLocationForConversation(
            channel(),
            const CustomerTicketAccess(
              serverSupported: true,
              permissionsLoaded: false,
              canView: false,
              canReply: false,
            ),
          ),
          isNull,
        );
      },
    );

    test(
      'kênh khác (Hỗ trợ, nhóm thường / người dùng tên "Ticket") vẫn mở phòng chat',
      () {
        expect(
          customerTicketLocationForConversation(
            channel(title: 'Hỗ trợ', slug: 'support'),
            canView,
          ),
          isNull,
        );
        expect(
          customerTicketLocationForConversation(
            channel(slug: null, automation: false),
            canView,
          ),
          isNull,
        );
        expect(
          customerTicketLocationForConversation(
            channel(
              slug: null,
              automation: false,
              kind: ConversationKind.direct,
              peerUserId: 'user-2',
            ),
            canView,
          ),
          isNull,
        );
      },
    );
  });

  test('customerTicketInboxLocation bỏ workspace rỗng', () {
    expect(customerTicketInboxLocation(' '), '/customer-tickets');
    expect(
      customerTicketInboxLocation('ws-1'),
      '/customer-tickets?workspaceId=ws-1',
    );
  });
}

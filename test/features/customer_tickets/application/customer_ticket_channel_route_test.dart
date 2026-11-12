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
  }) {
    return ConversationSummary(
      id: 'c1',
      workspaceId: 'ws-1',
      channelId: 'kenh-ticket',
      kind: ConversationKind.channel,
      title: title,
      preview: '',
      updatedAt: DateTime(2026, 11, 12),
      isAutomation: automation,
      slug: slug,
    );
  }

  group('customerTicketLocationForConversation', () {
    test(
      'kênh bot Ticket + xem được ticket: mở hộp thư ticket, kèm kênh để quay lại',
      () {
        final location = customerTicketLocationForConversation(
          channel(),
          canView,
        );

        final uri = Uri.parse(location!);
        expect(uri.path, '/customer-tickets');
        expect(uri.queryParameters, {
          'workspaceId': 'ws-1',
          'channelId': 'kenh-ticket',
          'channelTitle': 'Ticket',
        });
      },
    );

    test('máy chủ cũ không trả slug: nhận ra kênh bot theo tên "Ticket"', () {
      expect(
        customerTicketLocationForConversation(channel(slug: null), canView),
        isNotNull,
      );
    });

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

    test('kênh khác (Hỗ trợ, nhóm thường tên "Ticket") vẫn mở phòng chat', () {
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
    });
  });

  group('customerTicketChannelChatLocation', () {
    test('dựng đường phòng chat của kênh Ticket', () {
      final uri = Uri.parse(
        customerTicketChannelChatLocation(
          channelId: 'kenh-ticket',
          channelTitle: 'Ticket',
          workspaceId: 'ws-1',
        )!,
      );
      expect(uri.path, '/conversations/kenh-ticket');
      expect(uri.queryParameters, {
        'workspaceId': 'ws-1',
        'title': 'Ticket',
        'kind': 'channel',
      });
    });

    test('không biết kênh thì không có nút', () {
      expect(
        customerTicketChannelChatLocation(
          channelId: ' ',
          channelTitle: 'Ticket',
          workspaceId: 'ws-1',
        ),
        isNull,
      );
    });
  });
}

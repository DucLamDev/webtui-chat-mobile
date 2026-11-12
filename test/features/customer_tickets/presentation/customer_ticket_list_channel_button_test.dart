import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/customer_tickets/application/customer_ticket_access_policy.dart';
import 'package:webtui_chat/features/customer_tickets/presentation/controllers/customer_ticket_access_provider.dart';
import 'package:webtui_chat/features/customer_tickets/presentation/screens/customer_ticket_list_screen.dart';

void main() {
  Future<void> pumpScreen(WidgetTester tester, {String? channelId}) {
    return tester.pumpWidget(
      ProviderScope(
        overrides: [
          customerTicketAccessProvider.overrideWith(
            (ref) => const CustomerTicketAccess.unavailable(),
          ),
        ],
        child: MaterialApp(
          home: CustomerTicketListScreen(
            workspaceId: 'ws-1',
            channelId: channelId,
            channelTitle: 'Ticket',
          ),
        ),
      ),
    );
  }

  testWidgets('vào từ kênh Ticket: có nút mở lại kênh chat Ticket', (
    tester,
  ) async {
    await pumpScreen(tester, channelId: 'kenh-ticket');

    expect(find.byTooltip('Mở kênh chat Ticket'), findsOneWidget);
  });

  testWidgets('vào từ ô Ticket khách (không có kênh): không có nút', (
    tester,
  ) async {
    await pumpScreen(tester);

    expect(find.byTooltip('Mở kênh chat Ticket'), findsNothing);
  });
}

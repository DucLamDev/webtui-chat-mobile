import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/approvals/domain/entities/approval.dart';
import 'package:webtui_chat/features/customer_tickets/domain/entities/customer_ticket.dart';
import 'package:webtui_chat/features/customer_tickets/presentation/widgets/customer_ticket_formatters.dart';
import 'package:webtui_chat/features/customer_tickets/presentation/widgets/customer_ticket_states.dart';
import 'package:webtui_chat/features/inbox/domain/entities/inbox.dart';
import 'package:webtui_chat/l10n/app_strings.dart';

void main() {
  void useEnglish() {
    AppStrings.current = const AppStringsEn();
    addTearDown(() => AppStrings.current = const AppStringsVi());
  }

  test('nhãn trạng thái ticket và thời gian chờ đổi sang tiếng Anh', () {
    expect(
      customerTicketStatusLabel(CustomerTicketStatus.unanswered),
      'Chưa trả lời',
    );
    expect(customerTicketWaitingLabel(5), 'Chờ 5 phút');
    useEnglish();
    expect(
      customerTicketStatusLabel(CustomerTicketStatus.unanswered),
      'Unanswered',
    );
    expect(
      customerTicketStatusLabel(CustomerTicketStatus.answered),
      'Answered',
    );
    expect(customerTicketWaitingLabel(5), 'Waiting 5 min');
    expect(customerTicketWaitingLabel(0), 'Just sent');
    expect(customerTicketCategoryLabel('ky_thuat'), 'Technical');
  });

  test('tên bộ lọc hộp thư và phê duyệt tính lúc dùng', () {
    expect(InboxStatusFilter.open.label, 'Đang mở');
    expect(ApprovalFilter.done.label, 'Đã xử lý');
    useEnglish();
    expect(InboxStatusFilter.open.label, 'Open');
    expect(InboxAssigneeFilter.unassigned.label, 'Unassigned');
    expect(ApprovalFilter.pending.label, 'Pending');
    expect(ApprovalFilter.done.label, 'Done');
  });

  testWidgets('trạng thái không có quyền của ticket khách hiện tiếng Anh', (
    tester,
  ) async {
    useEnglish();
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: CustomerTicketNoAccessState())),
    );
    expect(find.text('No permission to view tickets'), findsOneWidget);
    expect(find.text('Không có quyền xem ticket'), findsNothing);
  });
}

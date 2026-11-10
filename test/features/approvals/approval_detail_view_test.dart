import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/approvals/application/approval_access_policy.dart';
import 'package:webtui_chat/features/approvals/data/datasources/approval_remote_data_source.dart';
import 'package:webtui_chat/features/approvals/domain/entities/approval.dart';
import 'package:webtui_chat/features/approvals/presentation/screens/approval_detail_screen.dart';
import 'package:webtui_chat/features/approvals/presentation/screens/approval_list_screen.dart';

ApprovalRequest _approval({
  required bool canDecide,
  String status = 'pending',
}) {
  return approvalFromMap({
    'id': 'a1',
    'status': status,
    'title': 'Chi 5 triệu',
    'action': 'payment.create',
    'source': 'webhook',
    'payload': {'amount': 5000000},
    'required_approvals': 1,
    'approvals_count': 0,
    'can_decide': canDecide,
  });
}

Future<void> _pump(WidgetTester tester, Widget child) {
  return tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
}

void main() {
  testWidgets('can_decide=true hiện nút và gửi quyết định kèm ghi chú', (
    tester,
  ) async {
    ApprovalDecisionKind? decided;
    String? note;
    await _pump(
      tester,
      ApprovalDetailView(
        approval: _approval(canDecide: true),
        onDecide: (decision, comment) async {
          decided = decision;
          note = comment;
        },
      ),
    );
    expect(find.text('Chi 5 triệu'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('approval_comment')), 'ổn');
    await tester.tap(find.byKey(const Key('approval_reject')));
    expect(decided, ApprovalDecisionKind.reject);
    expect(note, 'ổn');
  });

  testWidgets('can_decide=false ẩn nút Duyệt / Từ chối', (tester) async {
    await _pump(
      tester,
      ApprovalDetailView(
        approval: _approval(canDecide: false),
        onDecide: (_, _) async {},
      ),
    );
    expect(find.byKey(const Key('approval_approve')), findsNothing);
    expect(find.byKey(const Key('approval_reject')), findsNothing);
  });

  testWidgets('phiếu đã xử lý không còn nút dù can_decide=true', (
    tester,
  ) async {
    await _pump(
      tester,
      ApprovalDetailView(
        approval: _approval(canDecide: true, status: 'approved'),
        onDecide: (_, _) async {},
      ),
    );
    expect(find.byKey(const Key('approval_approve')), findsNothing);
  });

  testWidgets('máy chủ không hỗ trợ: báo không có quyền', (tester) async {
    await _pump(
      tester,
      approvalAccessGate(const ApprovalAccess.unavailable())!,
    );
    expect(find.byKey(const Key('approval_no_access')), findsOneWidget);
  });
}

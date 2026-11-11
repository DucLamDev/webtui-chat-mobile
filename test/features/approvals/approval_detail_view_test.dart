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
  _approvalStatusTests();
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

ApprovalRequest _full(Map<String, Object?> extra) => approvalFromMap({
  'id': 'a1',
  'title': 'Chi 5 triệu',
  'action': 'payment.create',
  ...extra,
});

void _approvalStatusTests() {
  group('nhãn trạng thái phiếu', () {
    String label(Map<String, Object?> json) => _full(json).display.label;

    test('pending / rejected / expired / cancelled', () {
      expect(label({'status': 'pending'}), 'Đang chờ');
      expect(label({'status': 'rejected'}), 'Đã từ chối');
      expect(label({'status': 'expired'}), 'Đã hết hạn');
      expect(label({'status': 'cancelled'}), 'Đã huỷ');
    });

    test('approved theo execution_mode, thiếu trường thì Đã duyệt', () {
      expect(
        label({'status': 'approved', 'execution_mode': 'internal'}),
        'Đã duyệt – đang thực hiện',
      );
      expect(
        label({'status': 'approved', 'execution_mode': 'external'}),
        'Đã duyệt – chờ bot thực hiện',
      );
      expect(
        label({'status': 'approved', 'execution_mode': 'none'}),
        'Đã duyệt',
      );
      expect(label({'status': 'approved'}), 'Đã duyệt');
    });

    test('executed: executor none là Đã duyệt, còn lại Đã thực hiện', () {
      expect(
        label({
          'status': 'executed',
          'result': {'executor': 'none'},
        }),
        'Đã duyệt',
      );
      expect(
        label({
          'status': 'executed',
          'result': {'executor': 'internal'},
        }),
        'Đã thực hiện',
      );
      expect(label({'status': 'executed'}), 'Đã thực hiện');
    });

    test('failed có lý do, giá trị lạ không crash', () {
      final failed = _full({
        'status': 'failed',
        'result': {'error': 'Hết hạn mức'},
      }).display;
      expect(failed.label, 'Thực hiện lỗi');
      expect(failed.detail, 'Hết hạn mức');
      expect(failed.tone, ApprovalStatusTone.error);
      expect(_full({'status': 'failed'}).display.detail, isNull);
      expect(label({'status': 'xyz'}), 'Đã cập nhật');
      expect(label({}), 'Đã cập nhật');
    });

    test('parse có / không có trường mới', () {
      final old = _full({'status': 'approved'});
      expect(old.executionMode, isNull);
      expect(old.executionStartedAt, isNull);
      expect(old.reportedAt, isNull);
      final fresh = _full({
        'status': 'approved',
        'execution_mode': 'external',
        'execution_started_at': '2026-11-11T01:00:00Z',
        'reported_at': null,
      });
      expect(fresh.executionMode, ApprovalExecutionMode.external);
      expect(fresh.executionStartedAt, isNotNull);
      expect(fresh.reportedAt, isNull);
    });
  });

  testWidgets('chi tiết hiện Thực hiện lỗi + lý do, màu lỗi', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorScheme: const ColorScheme.light()),
        home: Scaffold(
          body: ApprovalDetailView(
            approval: _full({
              'status': 'failed',
              'result': {'error': 'Cổng thanh toán từ chối'},
            }),
            onDecide: (_, _) async {},
          ),
        ),
      ),
    );
    expect(find.text('Thực hiện lỗi: Cổng thanh toán từ chối'), findsOneWidget);
    final text = tester.widget<Text>(
      find.byKey(const Key('approval_status_text')),
    );
    expect(text.style?.color, const ColorScheme.light().error);
  });
}

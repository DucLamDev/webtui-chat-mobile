import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/design_system/theme/webtui_theme.dart';
import 'package:webtui_chat/design_system/tokens/webtui_colors.dart';
import 'package:webtui_chat/features/ide_mobile/presentation/widgets/ai/ide_approval_sheet.dart';

Map<String, Object?> bash(String id, String cmd, {bool irreversible = false}) =>
    {
      'id': id,
      'method': 'claude/permission',
      'irreversible': irreversible,
      'params': {
        'tool_name': 'Bash',
        'input': {'command': cmd},
      },
    };

void main() {
  late List<Map<String, Object?>> calls;

  Future<void> pump(
    WidgetTester tester,
    List<Map<String, Object?>> approvals, {
    bool planPending = false,
    Object? plan,
    bool canControl = true,
    Brightness brightness = Brightness.light,
    List<List<String>>? approved,
    List<String>? deepened,
  }) async {
    calls = [];
    WebTuiColors.apply(brightness);
    await tester.pumpWidget(
      MaterialApp(
        theme: brightness == Brightness.dark
            ? WebTuiTheme.dark()
            : WebTuiTheme.light(),
        home: Scaffold(
          body: IdeApprovalSheet(
            approvals: approvals,
            planPending: planPending,
            plan: plan,
            canControl: canControl,
            onAnswer: (id, {required allow, answers, deepen = false}) =>
                calls.add({
                  'id': id,
                  'allow': allow,
                  'answers': answers,
                  'deepen': deepen,
                }),
            onApprovePlan: (d) => approved?.add(d),
            onDeepenPlan: () => deepened?.add('x'),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('lệnh: hiện câu lệnh, Cho phép / Từ chối', (tester) async {
    await pump(tester, [bash('a1', 'ls -la')]);
    expect(find.text('ls -la'), findsOneWidget);
    await tester.tap(find.byKey(const Key('ide_approval_allow_a1')));
    await tester.tap(find.byKey(const Key('ide_approval_deny_a1')));
    expect(calls[0], containsPair('allow', true));
    expect(calls[1], containsPair('allow', false));
  });

  testWidgets('sửa tệp: diff tô màu từ changes của Codex', (tester) async {
    await pump(tester, [
      {
        'id': 'e1',
        'method': 'item/fileChange/requestApproval',
        'changes': [
          {'path': '/srv/a.txt', 'diff': '@@ -1 +1 @@\n-cũ\n+mới'},
        ],
        'params': <String, Object?>{},
      },
    ]);
    expect(find.text('/srv/a.txt'), findsOneWidget);
    expect(find.text('+mới'), findsOneWidget);
    final plus = tester.widget<Container>(
      find
          .ancestor(of: find.text('+mới'), matching: find.byType(Container))
          .first,
    );
    expect(plus.color, isNotNull);
  });

  testWidgets('câu hỏi: chọn một / nhiều / tự gõ, gửi khoá theo header', (
    tester,
  ) async {
    await pump(tester, [
      {
        'id': 'q1',
        'method': 'claude/permission',
        'params': {
          'tool_name': 'AskUserQuestion',
          'input': {
            'questions': [
              {
                'question': 'Dùng DB nào?',
                'header': 'DB',
                'multiSelect': false,
                'options': [
                  {'label': 'Postgres', 'description': ''},
                  {'label': 'MySQL', 'description': ''},
                ],
              },
              {
                'question': 'Thêm gì?',
                'header': 'Them',
                'multiSelect': true,
                'options': [
                  {'label': 'Test', 'description': ''},
                  {'label': 'Doc', 'description': ''},
                ],
              },
            ],
          },
        },
      },
    ]);
    await tester.tap(find.byKey(const Key('ide_ask_option_DB_Postgres')));
    await tester.tap(find.byKey(const Key('ide_ask_option_DB_MySQL')));
    await tester.tap(find.byKey(const Key('ide_ask_option_Them_Test')));
    await tester.tap(find.byKey(const Key('ide_ask_option_Them_Doc')));
    await tester.enterText(find.byKey(const Key('ide_ask_free_Them')), 'Lint');
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('ide_approval_allow_q1')));
    await tester.tap(find.byKey(const Key('ide_approval_allow_q1')));
    expect(calls.single['answers'], {'DB': 'MySQL', 'Them': 'Test, Doc, Lint'});
    await tester.tap(find.byKey(const Key('ide_approval_deepen_q1')));
    expect(calls.last['deepen'], true);
  });

  testWidgets('câu hỏi Codex dùng id làm khoá', (tester) async {
    await pump(tester, [
      {
        'id': 'q2',
        'method': 'item/tool/requestUserInput',
        'params': {
          'questions': [
            {'id': 'qa', 'question': 'Tên?', 'options': <Object?>[]},
          ],
        },
      },
    ]);
    await tester.enterText(find.byKey(const Key('ide_ask_free_qa')), 'Lâm');
    await tester.tap(find.byKey(const Key('ide_approval_allow_q2')));
    expect(calls.single['answers'], {'qa': 'Lâm'});
  });

  testWidgets('kế hoạch ExitPlanMode: duyệt = allow', (tester) async {
    await pump(tester, [
      {
        'id': 'p1',
        'method': 'claude/permission',
        'params': {
          'tool_name': 'ExitPlanMode',
          'input': {'plan': '# Kế hoạch\n- làm A'},
        },
      },
    ]);
    expect(find.textContaining('làm A'), findsOneWidget);
    await tester.tap(find.byKey(const Key('ide_approval_allow_p1')));
    expect(calls.single, containsPair('allow', true));
  });

  testWidgets('planPending: điền sẵn "Đề xuất" rồi gửi decisions', (
    tester,
  ) async {
    final approved = <List<String>>[];
    final deepened = <String>[];
    await pump(
      tester,
      const [],
      planPending: true,
      plan:
          '## Cần bạn quyết\n- Dùng Redis không?\n  Đề xuất: Có\n\n## Việc\n- x',
      approved: approved,
      deepened: deepened,
    );
    expect(find.byKey(const Key('ide_plan_pending')), findsOneWidget);
    await tester.tap(find.byKey(const Key('ide_plan_approve')));
    expect(approved.single, ['Có']);
    await tester.tap(find.byKey(const Key('ide_plan_deepen')));
    expect(deepened, isNotEmpty);
  });

  testWidgets('cả loạt: chỉ lệnh / sửa tệp thường, không có irreversible', (
    tester,
  ) async {
    await pump(tester, [
      bash('b1', 'ls'),
      bash('b2', 'pwd'),
      bash('b3', 'rm -rf x', irreversible: true),
    ]);
    await tester.tap(find.byKey(const Key('ide_approval_batch')));
    expect(calls.map((c) => c['id']), ['b1', 'b2']);
  });

  testWidgets('irreversible: nhãn Quan trọng + nút vân tay', (tester) async {
    await pump(tester, [bash('r1', 'git push --force', irreversible: true)]);
    expect(find.byKey(const Key('ide_approval_important')), findsOneWidget);
    expect(find.text('Đồng ý bằng vân tay'), findsOneWidget);
    expect(find.byKey(const Key('ide_approval_batch')), findsNothing);
  });

  testWidgets('chỉ xem: không có nút duyệt', (tester) async {
    await pump(tester, [bash('a1', 'ls')], canControl: false);
    expect(find.byKey(const Key('ide_approval_allow_a1')), findsNothing);
  });

  testWidgets('nền tối vẫn dựng được', (tester) async {
    await pump(tester, [bash('a1', 'ls')], brightness: Brightness.dark);
    expect(find.text('ls'), findsOneWidget);
    WebTuiColors.apply(Brightness.light);
  });
}

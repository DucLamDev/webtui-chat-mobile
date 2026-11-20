import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/design_system/components/webtui_components.dart';
import 'package:webtui_chat/features/ide_mobile/presentation/screens/more/ide_ailog_screen.dart';
import 'package:webtui_chat/features/ide_mobile/presentation/screens/more/ide_changelog_screen.dart';
import 'package:webtui_chat/features/ide_mobile/presentation/screens/more/ide_kientruc_screen.dart';
import 'package:webtui_chat/features/ide_mobile/presentation/screens/more/ide_more_tab.dart';
import 'package:webtui_chat/features/ide_mobile/presentation/screens/more/ide_notes_screen.dart';
import 'package:webtui_chat/features/ide_mobile/presentation/screens/more/ide_oplog_screen.dart';
import 'package:webtui_chat/features/ide_mobile/presentation/screens/more/ide_report_screen.dart';
import 'package:webtui_chat/features/ide_mobile/presentation/screens/more/ide_tasks_screen.dart';

import 'support/more_env.dart';
import 'support/rpc_env.dart';

/// Mỗi màn: op tải dữ liệu, dữ liệu rỗng, và màn dựng.
final _cases = <(String, String, Object?, Widget Function())>[
  (
    'việc',
    'tasks.list',
    {'viewer': 'lam', 'tasks': []},
    () => const IdeTasksScreen(),
  ),
  (
    'nhật ký AI',
    'ailog.list',
    {'sessions': [], 'prs': []},
    () => const IdeAiLogScreen(project: 'web'),
  ),
  (
    'nhật ký thao tác',
    'oplog.list',
    {'events': [], 'next': null},
    () => const IdeOplogScreen(project: 'web'),
  ),
  (
    'ghi chú',
    'notes.list',
    {'notes': [], 'deleted': []},
    () => const IdeNotesScreen(project: 'web'),
  ),
  (
    'kiến trúc',
    'kientruc.read',
    {'exists': false},
    () => const IdeKientrucScreen(project: 'web'),
  ),
  (
    'changelog',
    'changelog.read',
    {'items': []},
    () => const IdeChangelogScreen(),
  ),
];

void main() {
  for (final (name, op, empty, build) in _cases) {
    group('trạng thái: $name', () {
      testWidgets('đang tải', (tester) async {
        final env = await pumpMore(
          tester,
          build(),
          (o, a) => ideFakeSilent,
          ops: {op},
        );
        expect(find.byType(WebTuiLoadingState), findsOneWidget);
        await tester.runAsync(env.dispose);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 6));
      });

      testWidgets('rỗng', (tester) async {
        await pumpMore(tester, build(), (o, a) => empty, ops: {op});
        expect(find.byType(WebTuiEmptyState), findsOneWidget);
        expect(find.byType(WebTuiErrorState), findsNothing);
      });

      testWidgets('lỗi rồi thử lại được', (tester) async {
        var fail = true;
        await pumpMore(tester, build(), (o, a) {
          if (fail) return const IdeFakeError('internal', 'Máy chủ lỗi tạm');
          return empty;
        }, ops: {op});
        expect(find.byType(WebTuiErrorState), findsOneWidget);
        expect(find.text('Máy chủ lỗi tạm'), findsOneWidget);
        fail = false;
        await tester.tap(find.text('Thử lại'));
        await settle(tester, 4);
        expect(find.byType(WebTuiErrorState), findsNothing);
        expect(find.byType(WebTuiEmptyState), findsOneWidget);
      });

      testWidgets('không quyền hiện đúng message', (tester) async {
        await pumpMore(
          tester,
          build(),
          (o, a) =>
              const IdeFakeError('forbidden', 'Bạn không thuộc dự án này'),
          ops: {op},
        );
        expect(find.text('Không có quyền'), findsOneWidget);
        expect(find.text('Bạn không thuộc dự án này'), findsOneWidget);
      });
    });
  }

  group('báo cáo', () {
    testWidgets('chạy báo cáo, hiện số liệu khi job xong', (tester) async {
      final env = await pumpMore(
        tester,
        const IdeReportScreen(
          project: 'web',
          pollInterval: Duration(milliseconds: 10),
        ),
        (o, a) => switch (o) {
          'report.self' => {'job': 'j1'},
          'jobs.tail' => {
            'text': '',
            'next': 0,
            'done': true,
            'result': {
              'generated_at': 1763548800,
              'my': false,
              'project': {'name': 'web', 'commits_7d': 7},
              'alerts': ['Cảnh báo thử'],
            },
          },
          _ => const IdeFakeError('internal'),
        },
        ops: {'report.self'},
      );
      await tester.tap(find.byKey(const Key('ide_report_run')));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await settle(tester, 6);
      expect(find.byKey(const Key('ide_report_facts')), findsOneWidget);
      expect(find.text('Cảnh báo thử'), findsOneWidget);
      expect(sentOps(env, 'report.self').first['project'], 'web');
      expect(sentOps(env, 'report.self').first.containsKey('ai'), isFalse);
    });

    testWidgets('công tắc AI chỉ có ở dự án riêng', (tester) async {
      await pumpMore(
        tester,
        const IdeReportScreen(project: 'web'),
        (o, a) => const IdeFakeError('internal'),
        ops: {'report.self'},
      );
      expect(find.byKey(const Key('ide_report_ai')), findsNothing);
      await pumpMore(
        tester,
        const IdeReportScreen(project: 'my:blog'),
        (o, a) => const IdeFakeError('internal'),
        ops: {'report.self'},
      );
      expect(find.byKey(const Key('ide_report_ai')), findsOneWidget);
    });
  });

  group('kiến trúc', () {
    testWidgets('hiện tiến độ, lỗi kiểm', (tester) async {
      await pumpMore(
        tester,
        const IdeKientrucScreen(project: 'web'),
        (o, a) => switch (o) {
          'kientruc.read' => {
            'exists': true,
            'sha': 'a' * 64,
            'data': {
              'name': 'H',
              'zones': [],
              'nodes': [],
              'edges': [],
              'risks': ['Lộ khoá'],
              'steps': [
                {'name': 'B1', 'done': true},
                {'name': 'B2', 'done': false},
              ],
            },
          },
          'kientruc.check' => {
            'ok': false,
            'issues': [
              {'level': 'loi', 'code': 'A', 'text': 'Thiếu vùng tin cậy'},
            ],
          },
          _ => const IdeFakeError('internal'),
        },
        ops: {'kientruc.read', 'kientruc.check'},
      );
      expect(find.byKey(const Key('ide_kientruc_list')), findsOneWidget);
      expect(find.byKey(const Key('ide_kientruc_progress')), findsOneWidget);
      expect(find.text('Lộ khoá'), findsWidgets);
    });
  });

  group('changelog', () {
    testWidgets('mục đầu mở sẵn', (tester) async {
      await pumpMore(
        tester,
        const IdeChangelogScreen(),
        (o, a) => {
          'version': '1.2.0',
          'items': [
            {
              'version': '1.2.0',
              'date': '01/01/2026',
              'title': 'Mới nhất',
              'body': 'Nội dung A',
            },
            {
              'version': '1.1.0',
              'date': '01/12/2025',
              'title': 'Cũ',
              'body': 'Nội dung B',
            },
          ],
        },
        ops: {'changelog.read'},
      );
      expect(find.byKey(const Key('ide_changelog_1.2.0')), findsOneWidget);
      expect(find.text('Nội dung A'), findsOneWidget);
      expect(find.text('Nội dung B'), findsNothing);
    });
  });

  group('tab Thêm', () {
    testWidgets('chỉ hiện mục có op, bấm đi đúng đường dẫn', (tester) async {
      final pushed = <String>[];
      await pumpMore(
        tester,
        const Scaffold(body: IdeMoreTab()),
        (o, a) => const IdeFakeError('internal'),
        ops: {'tasks.list', 'changelog.read', 'notes.list'},
        pushed: pushed,
      );
      expect(find.byKey(const Key('ide_more_tasks')), findsOneWidget);
      expect(find.byKey(const Key('ide_more_changelog')), findsOneWidget);
      expect(find.byKey(const Key('ide_more_notes')), findsOneWidget);
      expect(find.byKey(const Key('ide_more_oplog')), findsNothing);
      expect(find.byKey(const Key('ide_more_report')), findsNothing);
      await tester.tap(find.byKey(const Key('ide_more_notes')));
      await settle(tester, 4);
      expect(pushed.single, startsWith('/ide/notes?project='));
    });

    testWidgets('không có op nào thì báo rỗng', (tester) async {
      await pumpMore(
        tester,
        const Scaffold(body: IdeMoreTab()),
        (o, a) => const IdeFakeError('internal'),
        ops: {},
      );
      expect(find.byType(WebTuiEmptyState), findsOneWidget);
      expect(find.byKey(const Key('ide_more_grid')), findsNothing);
    });
  });
}

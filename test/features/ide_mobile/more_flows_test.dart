import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/design_system/components/webtui_components.dart';
import 'package:webtui_chat/features/ide_mobile/presentation/screens/more/ide_note_screen.dart';
import 'package:webtui_chat/features/ide_mobile/presentation/screens/more/ide_notes_screen.dart';
import 'package:webtui_chat/features/ide_mobile/presentation/screens/more/ide_oplog_screen.dart';
import 'package:webtui_chat/features/ide_mobile/presentation/screens/more/ide_task_detail_screen.dart';
import 'package:webtui_chat/features/ide_mobile/presentation/screens/more/ide_tasks_screen.dart';

import 'support/more_env.dart';
import 'support/rpc_env.dart';

Map<String, Object?> _task(
  String id, {
  String status = 'todo',
  Object? due,
  bool canManage = true,
  Object? suggestion,
}) => {
  'id': id,
  'project': 'web',
  'title': 'Việc $id',
  'status': status,
  'assignee': 'lam',
  'due': due,
  'updated': 1763548800,
  'can_manage': canManage,
  'suggestion': ?suggestion,
};

Map<String, Object?> _taskList(List<Map<String, Object?>> tasks) => {
  'viewer': 'lam',
  'assignable': {
    'web': {
      'members': ['an'],
    },
  },
  'tasks': tasks,
};

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.tap(f);
  await settle(tester, 8);
}

void main() {
  group('việc', () {
    testWidgets('lọc theo trạng thái, bấm thẻ mở chi tiết', (tester) async {
      final pushed = <String>[];
      await pumpMore(
        tester,
        const IdeTasksScreen(),
        (o, a) => _taskList([
          _task('aaaaaaaaaa'),
          _task('bbbbbbbbbb', status: 'done'),
        ]),
        ops: {'tasks.list'},
        pushed: pushed,
      );
      expect(find.byKey(const Key('ide_task_aaaaaaaaaa')), findsOneWidget);
      expect(find.byKey(const Key('ide_task_bbbbbbbbbb')), findsOneWidget);
      // Chip "Xong" (chỉ số 3): gọi thẳng bộ chọn của thanh lọc.
      tester
          .widget<WebTuiFilterChipBar>(find.byType(WebTuiFilterChipBar))
          .onSelected(3);
      await settle(tester, 3);
      expect(find.byKey(const Key('ide_task_aaaaaaaaaa')), findsNothing);
      expect(find.byKey(const Key('ide_task_bbbbbbbbbb')), findsOneWidget);
      await _tap(tester, find.byKey(const Key('ide_task_bbbbbbbbbb')));
      expect(pushed.single, '/ide/tasks/bbbbbbbbbb');
    });

    testWidgets('thêm việc gửi đúng hạn cuối tháng và no_ai', (tester) async {
      final env = await pumpMore(
        tester,
        const IdeTasksScreen(project: 'web'),
        (o, a) => o == 'tasks.list' ? _taskList([]) : {'id': 'cccccccccc'},
        ops: {'tasks.list', 'tasks.add'},
        datePicker: (_, _) async => DateTime(2026, 1, 31, 23, 59),
      );
      await _tap(tester, find.byKey(const Key('ide_task_add')));
      // Gửi trống: báo lỗi tại chỗ, chưa gọi máy chủ.
      await _tap(tester, find.byKey(const Key('ide_task_submit')));
      expect(find.byKey(const Key('ide_task_error')), findsOneWidget);
      expect(sentOps(env, 'tasks.add'), isEmpty);
      await tester.enterText(
        find.byKey(const Key('ide_task_title')),
        '  Sửa lỗi  ',
      );
      await _tap(tester, find.byKey(const Key('ide_task_due')));
      await _tap(tester, find.byKey(const Key('ide_task_no_ai')));
      await _tap(tester, find.byKey(const Key('ide_task_submit')));
      final sent = sentOps(env, 'tasks.add').single;
      expect(sent['title'], 'Sửa lỗi');
      expect(sent['due'], '2026-01-31');
      expect(sent['no_ai'], true);
      expect(sent['project'], 'web');
      expect(sent['assignee'], 'lam');
      expect(find.byKey(const Key('ide_task_submit')), findsNothing);
    });

    testWidgets('máy chủ từ chối khi thêm: giữ form, hiện message', (
      tester,
    ) async {
      await pumpMore(
        tester,
        const IdeTasksScreen(project: 'web'),
        (o, a) => o == 'tasks.list'
            ? _taskList([])
            : const IdeFakeError('forbidden', 'Bạn không giao việc được'),
        ops: {'tasks.list', 'tasks.add'},
      );
      await _tap(tester, find.byKey(const Key('ide_task_add')));
      await tester.enterText(find.byKey(const Key('ide_task_title')), 'X');
      await _tap(tester, find.byKey(const Key('ide_task_submit')));
      expect(find.text('Bạn không giao việc được'), findsOneWidget);
      expect(find.byKey(const Key('ide_task_title')), findsOneWidget);
    });

    testWidgets('chi tiết: đổi trạng thái kèm ghi chú', (tester) async {
      var status = 'todo';
      final env = await pumpMore(
        tester,
        const IdeTaskDetailScreen(taskId: 'aaaaaaaaaa'),
        (o, a) {
          if (o == 'tasks.status') {
            status = a['status']! as String;
            return {};
          }
          return _task('aaaaaaaaaa', status: status, due: '2026-12-31');
        },
        ops: {'tasks.get', 'tasks.status'},
      );
      expect(find.byKey(const Key('ide_task_title_text')), findsOneWidget);
      await _tap(tester, find.text('Đang làm'));
      await tester.enterText(find.byType(TextField).last, 'bắt đầu');
      await _tap(tester, find.byKey(const Key('webtui_dialog_confirm')));
      final sent = sentOps(env, 'tasks.status').single;
      expect(sent['status'], 'doing');
      expect(sent['note'], 'bắt đầu');
    });

    testWidgets('chi tiết: không có quyền quản lý thì ẩn sửa / xoá', (
      tester,
    ) async {
      await pumpMore(
        tester,
        const IdeTaskDetailScreen(taskId: 'aaaaaaaaaa'),
        (o, a) => _task('aaaaaaaaaa', canManage: false),
        ops: {'tasks.get'},
      );
      expect(find.byKey(const Key('ide_task_edit')), findsNothing);
      await settle(tester, 8);
      expect(find.byKey(const Key('ide_task_delete')), findsNothing);
    });

    testWidgets('chi tiết: xoá việc gửi tasks.delete sau khi xác nhận', (
      tester,
    ) async {
      final env = await pumpMore(
        tester,
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              key: const Key('open_detail'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      const IdeTaskDetailScreen(taskId: 'aaaaaaaaaa'),
                ),
              ),
              child: const Text('mở'),
            ),
          ),
        ),
        (o, a) => o == 'tasks.delete' ? {} : _task('aaaaaaaaaa'),
        ops: {'tasks.get', 'tasks.delete'},
      );
      await _tap(tester, find.byKey(const Key('open_detail')));
      await _tap(tester, find.byKey(const Key('ide_task_delete')));
      expect(sentOps(env, 'tasks.delete'), isEmpty);
      await _tap(tester, find.text('Xoá việc'));
      expect(sentOps(env, 'tasks.delete').single['id'], 'aaaaaaaaaa');
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(const Key('ide_task_delete')), findsNothing);
    });

    testWidgets('chi tiết: gợi ý AI chạy nền, hỏi lại tới khi xong', (
      tester,
    ) async {
      var polls = 0;
      await pumpMore(
        tester,
        const IdeTaskDetailScreen(
          taskId: 'aaaaaaaaaa',
          suggestPoll: Duration(milliseconds: 20),
        ),
        (o, a) {
          if (o == 'tasks.suggest') return {};
          polls++;
          return _task(
            'aaaaaaaaaa',
            suggestion: polls < 3
                ? {'state': 'running'}
                : {'state': 'done', 'text': 'Gợi ý: làm A trước'},
          );
        },
        ops: {'tasks.get', 'tasks.suggest'},
      );
      await _tap(tester, find.byKey(const Key('ide_task_suggest')));
      for (
        var i = 0;
        i < 8 && find.textContaining('làm A trước').evaluate().isEmpty;
        i++
      ) {
        await settle(tester, 2);
      }
      expect(find.textContaining('làm A trước'), findsOneWidget);
      expect(find.byKey(const Key('ide_task_suggest_waiting')), findsNothing);
    });

    testWidgets('mã việc sai thì không gọi máy chủ qua form', (tester) async {
      await pumpMore(
        tester,
        const IdeTaskDetailScreen(taskId: 'aaaaaaaaaa'),
        (o, a) => const IdeFakeError('not_found', 'Việc không còn'),
        ops: {'tasks.get'},
      );
      expect(find.text('Việc không còn'), findsOneWidget);
    });
  });

  group('nhật ký thao tác', () {
    Map<String, Object?> page(List<double> ts, Object? next) => {
      'matched': 3,
      'next': next,
      'summary': {
        'total': 3,
        'bad': 0,
        'kinds': {'git': 3},
      },
      'events': [
        for (final t in ts)
          {
            'ts': t,
            'kind': 'git',
            'action': 'push',
            'user': 'lam',
            'detail': 'lần ${t.toInt()}',
          },
      ],
    };

    testWidgets('tải thêm gửi before = next, lọc loại gửi kinds', (
      tester,
    ) async {
      final env = await pumpMore(
        tester,
        const IdeOplogScreen(project: 'web'),
        (o, a) =>
            a['before'] == null ? page([300, 200], 200) : page([100], null),
        ops: {'oplog.list'},
      );
      expect(find.byKey(const Key('ide_oplog_list')), findsOneWidget);
      expect(find.textContaining('lần 300'), findsOneWidget);
      await _tap(tester, find.byKey(const Key('ide_oplog_more')));
      final second = sentOps(env, 'oplog.list').last;
      expect(second['before'], 200);
      expect(find.textContaining('lần 100'), findsOneWidget);
      expect(find.byKey(const Key('ide_oplog_more')), findsNothing);
    });
  });

  group('ghi chú', () {
    Map<String, Object?> note(String body, String sha) => {
      'id': '0123456789ab',
      'title': 'Ghi chú A',
      'body': body,
      'sha': sha,
      'kind': 'ghi-chu',
    };

    testWidgets('danh sách bấm mở đúng đường dẫn kèm dự án', (tester) async {
      final pushed = <String>[];
      await pumpMore(
        tester,
        const IdeNotesScreen(project: 'web'),
        (o, a) => {
          'notes': [
            {'id': '0123456789ab', 'title': 'Ghi chú A'},
          ],
          'deleted': [],
        },
        ops: {'notes.list'},
        pushed: pushed,
      );
      await _tap(tester, find.byKey(const Key('ide_note_0123456789ab')));
      expect(pushed.single, contains('/ide/notes/0123456789ab'));
      expect(pushed.single, contains('project=web'));
    });

    testWidgets(
      'lưu bị lệch phiên bản: giữ chữ đã gõ, "giữ chữ của tôi" lưu bằng sha mới',
      (tester) async {
        var sha = 'a' * 64;
        var saves = 0;
        final env = await pumpMore(
          tester,
          const IdeNoteScreen(project: 'web', noteId: '0123456789ab'),
          (o, a) {
            if (o == 'notes.save') {
              saves++;
              if (saves == 1) {
                return const IdeFakeError('conflict', 'Có người vừa sửa');
              }
              return {'sha': 'c' * 64};
            }
            return note('nội dung cũ', sha);
          },
          ops: {'notes.read', 'notes.save'},
        );
        await _tap(tester, find.byKey(const Key('ide_note_edit')));
        await tester.enterText(
          find.byKey(const Key('ide_note_body')),
          'chữ của tôi',
        );
        sha = 'b' * 64; // bản mới trên máy chủ
        await _tap(tester, find.byKey(const Key('ide_note_save')));
        expect(find.byKey(const Key('ide_note_conflict')), findsOneWidget);
        expect(find.text('chữ của tôi'), findsOneWidget);
        await _tap(tester, find.byKey(const Key('ide_note_conflict_keep')));
        expect(find.byKey(const Key('ide_note_conflict')), findsNothing);
        expect(find.text('chữ của tôi'), findsOneWidget);
        await _tap(tester, find.byKey(const Key('ide_note_save')));
        final last = sentOps(env, 'notes.save').last;
        expect(last['sha'], 'b' * 64);
        expect(last['body'], 'chữ của tôi');
        expect(find.byKey(const Key('ide_note_save')), findsNothing);
      },
    );

    testWidgets('lỗi quyền khi lưu hiện message, không mất chữ', (
      tester,
    ) async {
      await pumpMore(
        tester,
        const IdeNoteScreen(project: 'web', noteId: '0123456789ab'),
        (o, a) => o == 'notes.save'
            ? const IdeFakeError('forbidden', 'Bạn chỉ được xem')
            : note('x', 'a' * 64),
        ops: {'notes.read', 'notes.save'},
      );
      await _tap(tester, find.byKey(const Key('ide_note_edit')));
      await tester.enterText(find.byKey(const Key('ide_note_body')), 'mới');
      await _tap(tester, find.byKey(const Key('ide_note_save')));
      expect(find.text('Bạn chỉ được xem'), findsOneWidget);
      expect(find.text('mới'), findsOneWidget);
    });

    testWidgets('ghi chú sơ đồ chỉ xem, không có nút sửa', (tester) async {
      await pumpMore(
        tester,
        const IdeNoteScreen(project: 'web', noteId: '0123456789ab'),
        (o, a) => {...note('{}', 'a' * 64), 'kind': 'so-do'},
        ops: {'notes.read'},
      );
      expect(find.byKey(const Key('ide_note_edit')), findsNothing);
      expect(find.byKey(const Key('ide_note_diagram_hint')), findsOneWidget);
    });

    testWidgets('đang sửa dở mà thoát thì hỏi lại', (tester) async {
      await pumpMore(
        tester,
        const IdeNoteScreen(project: 'web', noteId: '0123456789ab'),
        (o, a) => note('x', 'a' * 64),
        ops: {'notes.read'},
      );
      await _tap(tester, find.byKey(const Key('ide_note_edit')));
      await tester.enterText(find.byKey(const Key('ide_note_body')), 'đã gõ');
      await _tap(tester, find.byKey(const Key('ide_note_cancel')));
      expect(find.byKey(const Key('webtui_dialog_confirm')), findsOneWidget);
    });

    testWidgets('phiên bản cũ: khôi phục gửi notes.restore', (tester) async {
      final env = await pumpMore(
        tester,
        const IdeNoteScreen(project: 'web', noteId: '0123456789ab'),
        (o, a) => switch (o) {
          'notes.versions' => {
            'items': [
              {'n': 2, 'title': 'T', 'body': 'bản hai'},
            ],
          },
          'notes.restore' => {},
          _ => note('x', 'a' * 64),
        },
        ops: {'notes.read', 'notes.versions', 'notes.restore'},
      );
      await _tap(tester, find.byKey(const Key('ide_note_versions')));
      await _tap(tester, find.byKey(const Key('ide_note_version_2')));
      await _tap(tester, find.byKey(const Key('webtui_dialog_confirm')));
      expect(sentOps(env, 'notes.restore').single['n'], 2);
    });
  });
}

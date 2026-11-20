import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/ide_mobile/data/ide_rpc_client.dart';
import 'package:webtui_chat/features/ide_mobile/presentation/screens/projects/ide_deploy_screen.dart';
import 'package:webtui_chat/features/ide_mobile/presentation/widgets/projects/ide_project_ui.dart';

import 'support/project_env.dart';
import 'support/rpc_env.dart';

Map<String, Object?> _web() => proj(
  'web',
  kind: 'vps',
  targets: [
    {'name': 'prod'},
    {'name': 'test'},
  ],
);

final class _Sim {
  _Sim({this.preview, this.previewOk = true, this.runOk = true});
  Map<String, Object?>? preview;
  bool previewOk;
  bool runOk;
  final sent = <String, List<Map<String, Object?>>>{};
  final jobs = <String, bool>{};

  Object? call(String op, Map<String, Object?> a) {
    sent.putIfAbsent(op, () => []).add(a);
    switch (op) {
      case 'projects.list':
        return {
          'items': [_web()],
        };
      case 'deploy.preview':
        return {'job': 'pv${sent[op]!.length}'};
      case 'deploy.run':
        return {'job': 'run1'};
      case 'deploy.history':
        return {
          'items': [
            {
              'id': 'h1',
              'kind': 'run',
              'at': 1700000000,
              'by': 'an',
              'commit': 'abcdef12',
              'subject': 'Bản 1',
            },
          ],
        };
      case 'deploy.rollback':
        return {'job': 'rb1'};
      case 'jobs.tail':
        final job = '${a['job']}';
        if (job.startsWith('pv')) {
          return previewOk
              ? {
                  'text': '',
                  'next': 0,
                  'status': 'done',
                  'done': true,
                  'result': preview ?? previewResult(),
                }
              : {
                  'text': 'lỗi kết nối máy chủ\n',
                  'next': 1,
                  'status': 'failed',
                  'done': true,
                };
        }
        return {
          'text': '',
          'next': 0,
          'status': runOk ? 'done' : 'failed',
          'done': true,
          'result': {'ok': runOk},
        };
    }
    return <String, Object?>{};
  }
}

bool _enabled(WidgetTester t, String key) =>
    t.widget<IdeProjectButton>(find.byKey(Key(key))).onPressed != null;

Future<ProjectHarness> _pump(
  WidgetTester tester,
  Object sim, {
  IdeStepHandler? step,
  List<String>? ops,
}) => pumpProject(
  tester,
  sim is _Sim ? sim.call : sim as IdeFakeHandler,
  const IdeDeployScreen(project: 'web'),
  step: step,
  ops: ops ?? ideProjectTestOps,
);

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.tap(find.byKey(Key(key)));
  await pumpFor(tester);
}

void main() {
  testWidgets('chưa xem trước thì nút Triển khai tắt', (tester) async {
    final sim = _Sim();
    await _pump(tester, sim);
    expect(find.byKey(const Key('ide_deploy_idle')), findsOneWidget);
    expect(_enabled(tester, 'ide_deploy_run'), isFalse);
    expect(sim.sent['deploy.run'], isNull);
  });

  testWidgets('xem trước rồi triển khai: gửi preview + target, chỉ một lần', (
    tester,
  ) async {
    final sim = _Sim();
    await _pump(tester, sim);
    await _tap(tester, 'ide_deploy_preview');
    expect(sim.sent['deploy.preview']!.single, {
      'project': 'web',
      'target': 'prod',
    });
    expect(find.byKey(const Key('ide_preview_group_A')), findsOneWidget);
    expect(find.byKey(const Key('ide_preview_group_D')), findsOneWidget);
    expect(find.byKey(const Key('ide_preview_warning')), findsOneWidget);
    expect(_enabled(tester, 'ide_deploy_run'), isTrue);
    await _tap(tester, 'ide_deploy_run');
    final run = sim.sent['deploy.run']!.single;
    expect(run['preview'], 'pv1');
    expect(run['target'], 'prod');
    expect(run.containsKey('allow_many_delete'), isFalse);
    expect(find.byKey(const Key('ide_deploy_ok')), findsOneWidget);
    expect(_enabled(tester, 'ide_deploy_run'), isFalse);
  });

  testWidgets('đổi máy sau khi xem trước thì phải xem lại', (tester) async {
    final sim = _Sim();
    await _pump(tester, sim);
    await _tap(tester, 'ide_deploy_preview');
    expect(_enabled(tester, 'ide_deploy_run'), isTrue);
    await _tap(tester, 'ide_deploy_target_test');
    expect(_enabled(tester, 'ide_deploy_run'), isFalse);
    expect(find.byKey(const Key('ide_deploy_block')), findsOneWidget);
  });

  testWidgets('bản xem trước quá 15 phút thì tắt nút', (tester) async {
    final sim = _Sim();
    final h = await _pump(tester, sim);
    await _tap(tester, 'ide_deploy_preview');
    expect(_enabled(tester, 'ide_deploy_run'), isTrue);
    h.clock.now = h.clock.now.add(const Duration(minutes: 16));
    await tester.pump(const Duration(minutes: 16));
    expect(_enabled(tester, 'ide_deploy_run'), isFalse);
    expect(sim.sent['deploy.run'], isNull);
  });

  testWidgets('xoá nhiều: hỏi lại; huỷ thì không gửi, đồng ý thì có cờ', (
    tester,
  ) async {
    final sim = _Sim(preview: previewResult(deleteMany: true));
    await _pump(tester, sim);
    await _tap(tester, 'ide_deploy_preview');
    expect(find.byKey(const Key('ide_preview_delete_many')), findsOneWidget);
    await _tap(tester, 'ide_deploy_run');
    await tester.tap(find.text('Dừng lại').last);
    await pumpFor(tester);
    expect(sim.sent['deploy.run'], isNull);
    expect(_enabled(tester, 'ide_deploy_run'), isTrue);
    await _tap(tester, 'ide_deploy_run');
    await tester.tap(find.text('Vẫn triển khai').last);
    await pumpFor(tester);
    expect(sim.sent['deploy.run']!.single['allow_many_delete'], isTrue);
  });

  testWidgets('vân tay huỷ thì không triển khai, nút vẫn bấm lại được', (
    tester,
  ) async {
    final sim = _Sim();
    var asked = 0;
    final h = await _pump(
      tester,
      (op, a) => op == 'deploy.run' ? ideFakeSilent : sim.call(op, a),
      step: (r) async {
        asked++;
        return null;
      },
    );
    await _tap(tester, 'ide_deploy_preview');
    await tester.ensureVisible(find.byKey(const Key('ide_deploy_run')));
    await tester.tap(find.byKey(const Key('ide_deploy_run')));
    await pumpFor(tester);
    final req = h.env.lastSocket!.sentOfType('op').last['req'];
    h.env.lastSocket!.emit({
      'type': 'need_step',
      'req': req,
      'challenge': 'Y2g=',
      'summary': 'Triển khai',
    });
    await pumpFor(tester, 12);
    expect(asked, 1);
    expect(h.env.lastSocket!.sentOfType('step'), isEmpty);
    expect(find.byKey(const Key('ide_deploy_ok')), findsNothing);
    expect(_enabled(tester, 'ide_deploy_run'), isTrue);
  });

  testWidgets('xem trước lỗi: hiện lỗi và nút thử lại', (tester) async {
    final sim = _Sim(previewOk: false);
    await _pump(tester, sim);
    await _tap(tester, 'ide_deploy_preview');
    expect(find.byKey(const Key('ide_preview_failed')), findsOneWidget);
    expect(find.textContaining('lỗi kết nối máy chủ'), findsOneWidget);
    expect(_enabled(tester, 'ide_deploy_run'), isFalse);
    expect(find.byKey(const Key('ide_preview_retry')), findsOneWidget);
  });

  testWidgets('triển khai lỗi: báo lỗi, không báo thành công', (tester) async {
    final sim = _Sim(runOk: false);
    await _pump(tester, sim);
    await _tap(tester, 'ide_deploy_preview');
    await _tap(tester, 'ide_deploy_run');
    expect(find.byKey(const Key('ide_deploy_failed')), findsOneWidget);
    expect(find.byKey(const Key('ide_deploy_ok')), findsNothing);
  });

  testWidgets('không quyền: hiện thông báo quyền, không gọi tiếp', (
    tester,
  ) async {
    final sim = _Sim();
    await _pump(
      tester,
      (op, a) => op == 'deploy.preview'
          ? const IdeFakeError('forbidden')
          : sim.call(op, a),
    );
    await _tap(tester, 'ide_deploy_preview');
    expect(find.byKey(const Key('ide_preview_failed')), findsOneWidget);
    expect(_enabled(tester, 'ide_deploy_run'), isFalse);
  });

  testWidgets('IDE chưa có op deploy thì báo chưa hỗ trợ', (tester) async {
    final sim = _Sim();
    await _pump(
      tester,
      sim,
      ops: ideProjectTestOps.where((o) => !o.startsWith('deploy.')).toList(),
    );
    expect(find.byKey(const Key('ide_deploy_unsupported')), findsOneWidget);
    expect(find.byKey(const Key('ide_deploy_run')), findsNothing);
  });

  testWidgets('lịch sử: quay lui chạy deploy.rollback', (tester) async {
    final sim = _Sim();
    await _pump(tester, sim);
    await _tap(tester, 'ide_deploy_history');
    expect(find.byKey(const Key('ide_history_h1')), findsOneWidget);
    await tester.tap(find.byKey(const Key('ide_history_rollback_h1')));
    await pumpFor(tester);
    await tester.tap(find.byType(FilledButton).last);
    await pumpFor(tester);
    expect(sim.sent['deploy.rollback']!.single['project'], 'web');
  });

  testWidgets('nền tối vẫn dựng được', (tester) async {
    final sim = _Sim();
    await pumpProject(
      tester,
      sim.call,
      const IdeDeployScreen(project: 'web'),
      brightness: Brightness.dark,
    );
    expect(find.byKey(const Key('ide_deploy_preview')), findsOneWidget);
  });

  testWidgets('xoá nhiều mà danh sách bị cắt: hộp hỏi ghi ít nhất', (
    tester,
  ) async {
    final sim = _Sim(
      preview: {...previewResult(deleteMany: true), 'truncated': true},
    );
    await _pump(tester, sim);
    await _tap(tester, 'ide_deploy_preview');
    await _tap(tester, 'ide_deploy_run');
    expect(find.textContaining('ít nhất'), findsOneWidget);
    expect(find.textContaining('log đầy đủ'), findsOneWidget);
  });

  testWidgets('quay bản cũ: hộp xác nhận ghi tên máy đích', (tester) async {
    final sim = _Sim();
    await _pump(tester, sim);
    await _tap(tester, 'ide_deploy_history');
    await tester.tap(find.byKey(const Key('ide_history_rollback_h1')));
    await pumpFor(tester);
    expect(find.textContaining('"prod"'), findsOneWidget);
  });

  testWidgets('lượt triển khai mới: không còn nút Xem log của job cũ', (
    tester,
  ) async {
    final sim = _Sim();
    var runs = 0;
    await _pump(tester, (op, a) {
      if (op == 'deploy.run' && ++runs == 2) {
        return const IdeFakeError('boom');
      }
      return sim.call(op, a);
    });
    await _tap(tester, 'ide_deploy_preview');
    await _tap(tester, 'ide_deploy_run');
    expect(find.text('Xem log'), findsOneWidget);
    await _tap(tester, 'ide_deploy_preview');
    await _tap(tester, 'ide_deploy_run');
    expect(find.byKey(const Key('ide_deploy_failed')), findsOneWidget);
    expect(find.text('Xem log'), findsNothing);
  });

  testWidgets('Kéo về: hỏi xác nhận có số tệp đang đổi, huỷ thì không gửi', (
    tester,
  ) async {
    final sim = _Sim();
    await _pump(tester, (op, a) {
      if (op == 'projects.info') return {'dirty': 3};
      if (op == 'deploy.pull') {
        sim.sent.putIfAbsent(op, () => []).add(a);
        return {'job': 'pl1'};
      }
      return sim.call(op, a);
    });
    await _tap(tester, 'ide_deploy_pull');
    await tester.tap(find.byKey(const Key('ide_pull_all')));
    await pumpFor(tester);
    expect(find.textContaining('bị thay bằng bản trên máy chủ'), findsOneWidget);
    expect(find.textContaining('3 tệp đang thay đổi'), findsOneWidget);
    await tester.tap(find.text('Huỷ').last);
    await pumpFor(tester);
    expect(sim.sent['deploy.pull'], isNull);
    await _tap(tester, 'ide_deploy_pull');
    await tester.tap(find.byKey(const Key('ide_pull_newer')));
    await pumpFor(tester);
    await tester.tap(find.byType(FilledButton).last);
    await pumpFor(tester);
    expect(sim.sent['deploy.pull']!.single['newer'], isTrue);
  });

  testWidgets('lịch sử: hộp quay lại ghi mã commit, chữ giả dạng hiện rõ, '
      'khoá nút khi đang hỏi', (tester) async {
    final sim = _Sim();
    await _pump(tester, (op, a) {
      if (op == 'deploy.history') {
        return {
          'items': [
            {
              'id': 'abcdef1234',
              'kind': 'run',
              'at': 1700000000,
              'by': 'an',
              'subject': 'Bản\u202Egpj',
            },
          ],
        };
      }
      return sim.call(op, a);
    });
    await _tap(tester, 'ide_deploy_history');
    await tester.tap(find.byKey(const Key('ide_history_rollback_abcdef1234')));
    await pumpFor(tester);
    expect(find.textContaining('(abcdef1)'), findsOneWidget);
    expect(find.textContaining('<U+202E>'), findsWidgets);
    // Đang mở hộp hỏi: nút phía sau đã khoá chống bấm trùng.
    final btn = tester.widget<TextButton>(
      find.byKey(const Key('ide_history_rollback_abcdef1234')),
    );
    expect(btn.onPressed, isNull);
    await tester.tap(find.text('Huỷ').last);
    await pumpFor(tester);
    final again = tester.widget<TextButton>(
      find.byKey(const Key('ide_history_rollback_abcdef1234')),
    );
    expect(again.onPressed, isNotNull);
  });

  test('ideFormatUnix: số giây quá lớn không ném lỗi', () {
    expect(ideFormatUnix(10000000000000), '—');
    expect(ideFormatUnix(9223372036854775807), '—');
    expect(ideFormatUnix(0), '');
    expect(ideFormatUnix(1700000000), isNot('—'));
  });
}

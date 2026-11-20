import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/ide_mobile/data/ide_connection.dart';
import 'package:webtui_chat/features/ide_mobile/presentation/screens/projects/ide_projects_tab.dart';

import 'support/project_env.dart';
import 'support/rpc_env.dart';

final _info = {
  'branch': 'main',
  'ahead': 1,
  'behind': 0,
  'dirty': 3,
  'last_commit': {
    'sha': 'abc1234',
    'at': 1700000000,
    'by': 'an',
    'subject': 'x',
  },
};

final class _Sim {
  _Sim(this.projects);
  final List<Map<String, Object?>> projects;
  final sent = <String, List<Map<String, Object?>>>{};

  Object? call(String op, Map<String, Object?> a) {
    sent.putIfAbsent(op, () => []).add(a);
    return switch (op) {
      'projects.list' => {'items': projects},
      'projects.info' => _info,
      'pr.create' => {'job': 'pr1'},
      'git.merge' => {'job': 'mg1'},
      'jobs.tail' => {
        'text': '',
        'next': 0,
        'status': 'done',
        'done': true,
        'result': {'queued': true},
      },
      'vps.requests' => {'items': <Object?>[]},
      _ => <String, Object?>{},
    };
  }
}

Future<ProjectHarness> _pump(
  WidgetTester tester,
  Object handler, {
  List<String>? ops,
  IdeLinkPhase phase = IdeLinkPhase.ready,
  Brightness brightness = Brightness.light,
}) => pumpProject(
  tester,
  handler is _Sim ? handler.call : handler as IdeFakeHandler,
  const Scaffold(body: IdeProjectsTab()),
  ops: ops ?? ideProjectTestOps,
  phase: phase,
  brightness: brightness,
);

bool _has(String key) => find.byKey(Key(key)).evaluate().isNotEmpty;

void main() {
  testWidgets('chưa nối IDE thì báo nối trước', (tester) async {
    await _pump(tester, _Sim([]), phase: IdeLinkPhase.offline);
    expect(find.text('Chưa nối IDE'), findsOneWidget);
  });

  testWidgets('chưa có dự án: trạng thái rỗng', (tester) async {
    await _pump(tester, _Sim([]));
    expect(_has('ide_projects_empty'), isTrue);
  });

  testWidgets('đang tải: hiện chữ đang tải', (tester) async {
    await pumpProject(
      tester,
      (op, a) => ideFakeSilent,
      const Scaffold(body: IdeProjectsTab()),
      settleNow: false,
    );
    await tester.pump();
    expect(find.textContaining('Đang tải'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('lỗi tải dự án: hiện lỗi và nút thử lại', (tester) async {
    await _pump(tester, (op, a) => const IdeFakeError('boom'));
    expect(find.text('Thử lại'), findsWidgets);
  });

  testWidgets('không quyền: hiện trạng thái không quyền', (tester) async {
    await _pump(tester, (op, a) => const IdeFakeError('forbidden'));
    expect(_has('ide_forbidden'), isTrue);
  });

  testWidgets('dự án git: thông tin nhánh + đủ nút công ty', (tester) async {
    await _pump(
      tester,
      _Sim([
        proj(
          'web',
          targets: [
            {'name': 'prod'},
          ],
        ),
      ]),
    );
    expect(_has('ide_info_branch'), isTrue);
    for (final k in [
      'ide_act_pr',
      'ide_act_merge',
      'ide_act_mergeq',
      'ide_act_mergeq_mine',
      'ide_act_deploy',
      'ide_act_vps_request',
    ]) {
      expect(_has(k), isTrue, reason: k);
    }
    expect(_has('ide_act_to_git'), isFalse);
    expect(_has('ide_act_target'), isFalse);
  });

  testWidgets('dự án local: chỉ có Chuyển sang Git, không triển khai', (
    tester,
  ) async {
    await _pump(tester, _Sim([proj('lab', kind: 'local')]));
    expect(_has('ide_act_to_git'), isTrue);
    expect(_has('ide_act_deploy'), isFalse);
    expect(_has('ide_act_pr'), isFalse);
  });

  testWidgets('dự án riêng: có Máy đích, không có PR / hàng chờ công ty', (
    tester,
  ) async {
    await _pump(tester, _Sim([proj('my:blog', my: true)]));
    expect(_has('ide_act_target'), isTrue);
    expect(_has('ide_act_deploy'), isTrue);
    expect(_has('ide_act_pr'), isFalse);
    expect(_has('ide_act_mergeq'), isFalse);
    expect(_has('ide_act_vps_request'), isFalse);
  });

  testWidgets('IDE thiếu op: nút tương ứng ẩn; hết nút thì báo', (
    tester,
  ) async {
    await _pump(
      tester,
      _Sim([proj('web')]),
      ops: const ['projects.list', 'projects.info'],
    );
    expect(_has('ide_projects_no_actions'), isTrue);
  });

  testWidgets('quyền merge=false thì ẩn nút Gộp PR', (tester) async {
    await _pump(
      tester,
      _Sim([
        proj('web', can: {'merge': false}),
      ]),
    );
    expect(_has('ide_act_merge'), isFalse);
    expect(_has('ide_act_pr'), isTrue);
  });

  testWidgets('chọn dự án: tìm và đổi dự án', (tester) async {
    await _pump(tester, _Sim([proj('web'), proj('shop', kind: 'vps')]));
    await tester.tap(find.byKey(const Key('ide_project_picker')));
    await pumpFor(tester);
    expect(_has('ide_pick_shop'), isTrue);
    await tester.enterText(find.byType(TextField).last, 'zzz');
    await pumpFor(tester);
    expect(_has('ide_picker_empty'), isTrue);
    await tester.enterText(find.byType(TextField).last, 'sho');
    await pumpFor(tester);
    await tester.tap(find.byKey(const Key('ide_pick_shop')));
    await pumpFor(tester);
    expect(find.text('shop'), findsWidgets);
  });

  testWidgets('tạo PR: gửi tiêu đề, rồi mở màn việc nền', (tester) async {
    final sim = _Sim([proj('web')]);
    final h = await _pump(tester, sim);
    await tester.tap(find.byKey(const Key('ide_act_pr')));
    await pumpFor(tester);
    await tester.enterText(
      find.byKey(const Key('ide_pr_title')),
      '  Sửa lỗi  ',
    );
    await tester.tap(find.byKey(const Key('ide_pr_submit')));
    await pumpFor(tester);
    expect(sim.sent['pr.create']!.single, {
      'project': 'web',
      'title': 'Sửa lỗi',
    });
    expect(find.text('JOB pr1'), findsOneWidget);
    h.router.pop();
  });

  testWidgets('gộp PR được xếp hàng: báo và mở hàng chờ với số PR', (
    tester,
  ) async {
    final sim = _Sim([proj('web')]);
    await _pump(tester, sim);
    await tester.tap(find.byKey(const Key('ide_act_merge')));
    await pumpFor(tester);
    await tester.enterText(find.byKey(const Key('ide_merge_number')), '#42');
    await tester.tap(find.byKey(const Key('ide_merge_submit')));
    await pumpFor(tester, 12);
    expect(sim.sent['git.merge']!.single, {'project': 'web', 'number': 42});
    expect(find.textContaining('MERGEQ'), findsOneWidget);
    expect(find.textContaining('pr=42'), findsOneWidget);
  });

  testWidgets('gộp PR: số sai thì không gửi', (tester) async {
    final sim = _Sim([proj('web')]);
    await _pump(tester, sim);
    await tester.tap(find.byKey(const Key('ide_act_merge')));
    await pumpFor(tester);
    await tester.enterText(find.byKey(const Key('ide_merge_number')), '4x');
    await tester.tap(find.byKey(const Key('ide_merge_submit')));
    await pumpFor(tester);
    expect(sim.sent['git.merge'], isNull);
  });

  testWidgets('xin quyền máy chủ: lý do ngắn bị chặn, đủ thì gửi', (
    tester,
  ) async {
    final sim = _Sim([
      proj(
        'web',
        targets: [
          {'name': 'prod'},
        ],
      ),
    ]);
    await _pump(tester, sim);
    await tester.ensureVisible(find.byKey(const Key('ide_act_vps_request')));
    await tester.tap(find.byKey(const Key('ide_act_vps_request')));
    await pumpFor(tester);
    await tester.enterText(find.byKey(const Key('ide_vps_reason')), 'abc');
    await tester.tap(find.byKey(const Key('ide_vps_submit')));
    await pumpFor(tester);
    expect(sim.sent['vps.request'], isNull);
    expect(_has('ide_sheet_error'), isTrue);
    await tester.enterText(
      find.byKey(const Key('ide_vps_reason')),
      'Sửa lỗi gấp trên máy chủ',
    );
    await tester.tap(find.byKey(const Key('ide_vps_submit')));
    await pumpFor(tester);
    final r = sim.sent['vps.request']!.single;
    expect(r['target'], 'prod');
    expect(r['hours'], 1);
    expect(r['project'], 'web');
  });

  testWidgets('nền tối vẫn dựng được', (tester) async {
    await _pump(tester, _Sim([proj('web')]), brightness: Brightness.dark);
    expect(_has('ide_act_deploy'), isTrue);
  });

  testWidgets('dòng nhánh ghi rõ commit chưa đẩy lên', (tester) async {
    await _pump(
      tester,
      _Sim([
        proj(
          'web',
          targets: [
            {'name': 'prod'},
          ],
        ),
      ]),
    );
    expect(find.textContaining('1 commit chưa đẩy lên'), findsOneWidget);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/ide_mobile/presentation/screens/projects/ide_mergeq_screen.dart';
import 'package:webtui_chat/features/ide_mobile/presentation/widgets/projects/ide_job_result.dart';

import 'support/project_env.dart';
import 'support/rpc_env.dart';

Map<String, Object?> _view({bool changeMode = true, bool empty = false}) => {
  'hang_cho': 'web',
  'muc': 'hang-cho',
  'muc_ten': 'Hàng chờ',
  'hang': empty
      ? <Object?>[]
      : [
          {'so': 5, 'tieu_de': 'Sửa A', 'trang_thai': 'cho', 'rut': true},
          {'so': 6, 'tieu_de': 'Sửa B', 'trang_thai': 'cho', 'rut': false},
        ],
  'gan_day': empty
      ? <Object?>[]
      : [
          {
            'so': 4,
            'tieu_de': 'Cũ',
            'ket_qua': 'tra-ve',
            'ghi_chu': 'lỗi lint',
          },
        ],
  'viec_nhe': <Object?>[],
  'quyen': {
    'doi_muc': changeMode ? ['day-du', 'hang-cho', 'tat'] : <Object?>[],
    'merge': true,
  },
};

final class _Sim {
  _Sim({this.changeMode = true, this.empty = false});
  bool changeMode;
  bool empty;
  int views = 0;
  final sent = <String, List<Map<String, Object?>>>{};

  Object? call(String op, Map<String, Object?> a) {
    sent.putIfAbsent(op, () => []).add(a);
    switch (op) {
      case 'mergeq.view':
        views++;
        return _view(changeMode: changeMode, empty: empty);
      case 'mergeq.mine':
        return {
          'hang_cho': [
            {
              'hang_cho': 'web',
              'muc': 'hang-cho',
              'hang': [
                {'so': 9, 'tieu_de': 'Của tôi', 'trang_thai': 'cho'},
              ],
              'gan_day': <Object?>[],
            },
          ],
        };
      case 'mergeq.log':
        return {'text': 'dòng lỗi 1\n'};
    }
    return <String, Object?>{};
  }
}

Future<ProjectHarness> _pump(
  WidgetTester tester,
  Object sim, {
  String? project = 'web',
  int? pr,
  Duration refresh = const Duration(seconds: 10),
}) => pumpProject(
  tester,
  sim is _Sim ? sim.call : sim as IdeFakeHandler,
  IdeMergeqScreen(project: project, pr: pr, refreshInterval: refresh),
);

bool _has(String key) => find.byKey(Key(key)).evaluate().isNotEmpty;

void main() {
  testWidgets('hiện hàng chờ, PR gần đây và PR được nhắc tới', (tester) async {
    await _pump(tester, _Sim(), pr: 6);
    expect(_has('ide_mergeq_entry_5'), isTrue);
    expect(
      find.textContaining('Sửa B'),
      findsOneWidget,
    ); // PR được nhắc dùng GlobalKey để cuộn tới
    expect(_has('ide_mergeq_recent_4'), isTrue);
    expect(_has('ide_mergeq_withdraw_5'), isTrue);
    expect(_has('ide_mergeq_withdraw_6'), isFalse);
  });

  testWidgets('có quyền đổi mức thì có ChoiceChip, không thì ẩn', (
    tester,
  ) async {
    await _pump(tester, _Sim());
    expect(_has('ide_mergeq_mode_tat'), isTrue);
    await _pump(tester, _Sim(changeMode: false));
    expect(_has('ide_mergeq_mode_tat'), isFalse);
  });

  testWidgets('đổi mức: hỏi xác nhận rồi gọi mergeq.mode', (tester) async {
    final sim = _Sim();
    await _pump(tester, sim);
    await tester.tap(find.byKey(const Key('ide_mergeq_mode_tat')));
    await pumpFor(tester);
    expect(sim.sent['mergeq.mode'], isNull);
    await tester.tap(find.text('Đổi').last);
    await pumpFor(tester);
    expect(sim.sent['mergeq.mode']!.single['project'], 'web');
  });

  testWidgets('rút PR: xác nhận rồi gọi mergeq.withdraw', (tester) async {
    final sim = _Sim();
    await _pump(tester, sim);
    await tester.tap(find.byKey(const Key('ide_mergeq_withdraw_5')));
    await pumpFor(tester);
    await tester.tap(find.text('Rút PR').last);
    await pumpFor(tester);
    expect(sim.sent['mergeq.withdraw']!.single, {
      'project': 'web',
      'number': 5,
    });
  });

  testWidgets('xem log PR bị trả về', (tester) async {
    await _pump(tester, _Sim());
    await tester.ensureVisible(find.byKey(const Key('ide_mergeq_log_4')));
    await tester.tap(find.byKey(const Key('ide_mergeq_log_4')));
    await pumpFor(tester);
    expect(find.textContaining('dòng lỗi 1'), findsOneWidget);
  });

  testWidgets('hàng chờ trống: trạng thái rỗng', (tester) async {
    await _pump(tester, _Sim(empty: true));
    expect(_has('ide_mergeq_empty'), isTrue);
  });

  testWidgets('lỗi: có thử lại; không quyền: báo không quyền', (tester) async {
    await _pump(tester, (op, a) => const IdeFakeError('boom'));
    expect(find.text('Thử lại'), findsWidgets);
    await _pump(tester, (op, a) => const IdeFakeError('forbidden'));
    expect(_has('ide_forbidden'), isTrue);
  });

  testWidgets('không có dự án: hiện hàng chờ của tôi', (tester) async {
    final sim = _Sim();
    await _pump(tester, sim, project: null);
    expect(sim.sent['mergeq.mine'], isNotNull);
    expect(find.textContaining('Của tôi'), findsWidgets);
  });

  testWidgets('tự làm mới nền theo chu kỳ, không hiện vòng tải', (
    tester,
  ) async {
    final sim = _Sim();
    await _pump(tester, sim, refresh: const Duration(seconds: 10));
    final before = sim.views;
    await tester.pump(const Duration(seconds: 11));
    await pumpFor(tester);
    expect(sim.views, greaterThan(before));
    expect(_has('ide_mergeq_entry_5'), isTrue);
  });

  testWidgets('kết quả pr.create: số PR + nút mở gọi trình mở liên kết', (
    tester,
  ) async {
    final h = await pumpProject(
      tester,
      (op, a) => <String, Object?>{},
      const Scaffold(
        body: IdeJobResultView(
          op: 'pr.create',
          result: {
            'number': 12,
            'url': 'https://git.example/pr/12',
            'warnings': ['Chưa có test'],
          },
        ),
      ),
    );
    expect(find.byKey(const Key('ide_job_pr_number')), findsOneWidget);
    expect(find.text('Chưa có test'), findsOneWidget);
    await tester.tap(find.byKey(const Key('ide_job_pr_open')));
    await pumpFor(tester);
    expect(h.launched, ['https://git.example/pr/12']);
  });

  testWidgets('kết quả lạ thì không hiện gì', (tester) async {
    await pumpProject(
      tester,
      (op, a) => <String, Object?>{},
      const Scaffold(
        body: IdeJobResultView(op: 'pr.create', result: 'x'),
      ),
    );
    expect(_has('ide_job_pr_number'), isFalse);
  });
}

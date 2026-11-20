import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/app/providers/foundation_providers.dart';
import 'package:webtui_chat/design_system/theme/webtui_theme.dart';
import 'package:webtui_chat/design_system/tokens/webtui_colors.dart';
import 'package:webtui_chat/features/ide_mobile/data/ide_rpc_client.dart';
import 'package:webtui_chat/features/ide_mobile/presentation/screens/files/ide_trash_screen.dart';

import 'support/rpc_env.dart';

const _ops = [
  'files.trash',
  'files.restore',
  'files.purge',
  'files.trash_purge',
  'jobs.list',
];

Map<String, Object?> _trash() => {
  'items': [
    {
      'id': 't1',
      'path': '/srv/web/a.txt',
      'name': 'a.txt',
      't': 'f',
      'size': 12,
      'deleted_at': 1700000000000,
    },
  ],
};

Future<IdeRpcEnv> _pump(
  WidgetTester tester,
  IdeFakeHandler handler, {
  IdeStepHandler? step,
}) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  WebTuiColors.apply(Brightness.light);
  final env = IdeRpcEnv(handler, ops: _ops, step: step);
  addTearDown(() => tester.runAsync(env.dispose));
  await tester.runAsync(env.up);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [ideRpcClientProvider.overrideWithValue(env.rpc)],
      child: MaterialApp(
        theme: WebTuiTheme.light(),
        home: const IdeTrashScreen(root: '/srv/web'),
      ),
    ),
  );
  await settle(tester);
  return env;
}

void main() {
  testWidgets('thùng rác trống', (tester) async {
    await _pump(tester, (op, _) => op == 'files.trash' ? {'items': []} : {});
    expect(find.text('Thùng rác trống'), findsOneWidget);
  });

  testWidgets('lỗi tải có nút thử lại', (tester) async {
    await _pump(
      tester,
      (op, _) => op == 'files.trash' ? const IdeFakeError('internal') : {},
    );
    expect(find.text('Không mở được thùng rác'), findsOneWidget);
  });

  testWidgets('khôi phục gửi files.restore', (tester) async {
    final sent = <Map<String, Object?>>[];
    await _pump(tester, (op, a) {
      if (op == 'files.restore') {
        sent.add(a);
        return {'path': '/srv/web/a.txt'};
      }
      return _trash();
    });
    expect(find.text('a.txt'), findsOneWidget);
    await tester.tap(find.byKey(const Key('ide_trash_restore_t1')));
    await settle(tester);
    expect(sent.single, {'id': 't1'});
  });

  testWidgets('xoá hẳn: hỏi lại, rồi IDE đòi vân tay (need_step)', (
    tester,
  ) async {
    var steps = 0;
    final env = await _pump(
      tester,
      (op, a) => op == 'files.purge' ? ideFakeSilent : _trash(),
      step: (r) async {
        steps++;
        expect(r.op, 'files.purge');
        return 'chu-ky';
      },
    );
    await tester.tap(find.byKey(const Key('ide_trash_purge_t1')));
    await settle(tester);
    // chưa xác nhận thì chưa gọi gì
    expect(env.calls.where((c) => c == 'files.purge'), isEmpty);
    expect(find.text('Xoá hẳn "a.txt"?'), findsOneWidget);
    await tester.tap(find.text('Xoá hẳn').last);
    await settle(tester);
    expect(env.calls.where((c) => c == 'files.purge'), hasLength(1));
    final req = env.lastSocket!.sentOfType('op').last['req'];
    env.lastSocket!.emit({
      'type': 'need_step',
      'req': req,
      'challenge': 'Y2g=',
      'summary': 'Xoá hẳn',
    });
    await settle(tester);
    expect(steps, 1);
    expect(env.lastSocket!.sentOfType('step').single['sig'], 'chu-ky');
    env.lastSocket!.emit({
      'type': 'result',
      'req': req,
      'ok': true,
      'data': {},
    });
    await settle(tester);
  });

  testWidgets('bấm Huỷ ở hộp xác nhận thì không xoá', (tester) async {
    final env = await _pump(tester, (op, _) => _trash());
    await tester.tap(find.byKey(const Key('ide_trash_purge_t1')));
    await settle(tester);
    await tester.tap(find.text('Huỷ').last);
    await settle(tester);
    expect(env.calls.where((c) => c == 'files.purge'), isEmpty);
  });

  testWidgets('dọn hết cần xác nhận rồi gọi files.trash_purge', (tester) async {
    final sent = <Map<String, Object?>>[];
    await _pump(tester, (op, a) {
      if (op == 'files.trash_purge') {
        sent.add(a);
        return {'count': 1};
      }
      return _trash();
    });
    await tester.tap(find.byKey(const Key('ide_trash_purge_all')));
    await settle(tester);
    expect(sent, isEmpty);
    await tester.tap(find.text('Dọn sạch').last);
    await settle(tester);
    expect(sent.single, {'root': '/srv/web'});
  });
}

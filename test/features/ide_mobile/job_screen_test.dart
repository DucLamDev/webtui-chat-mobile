import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/app/providers/foundation_providers.dart';
import 'package:webtui_chat/design_system/theme/webtui_theme.dart';
import 'package:webtui_chat/design_system/tokens/webtui_colors.dart';
import 'package:webtui_chat/features/ide_mobile/presentation/screens/ide_job_screen.dart';

import 'support/rpc_env.dart';

Future<IdeRpcEnv> _pump(
  WidgetTester tester,
  IdeFakeHandler handler, {
  String jobId = 'j1',
}) async {
  WebTuiColors.apply(Brightness.light);
  final env = IdeRpcEnv(handler);
  addTearDown(() => tester.runAsync(env.dispose));
  await tester.runAsync(env.up);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [ideRpcClientProvider.overrideWithValue(env.rpc)],
      child: MaterialApp(
        theme: WebTuiTheme.light(),
        home: IdeJobScreen(
          jobId: jobId,
          pollInterval: const Duration(milliseconds: 100),
        ),
      ),
    ),
  );
  await settle(tester);
  return env;
}

/// Hẹn giờ của màn hình chạy theo đồng hồ giả: đẩy giờ rồi chờ tin giả tới.
Future<void> _poll(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 150));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
  }
  await tester.pump();
}

/// Gỡ màn hình, cho lượt hỏi đang bay về rồi hết hạn bộ hẹn giờ của rpc.
Future<void> _finish(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 60)),
  );
  await tester.pump(const Duration(seconds: 6));
}

Object? _listJob(String status) => {
  'items': [
    {
      'job': 'j1',
      'op': 'deploy',
      'project': 'web',
      'status': status,
      'started_at': '2026-11-19T10:00:00Z',
    },
  ],
};

void main() {
  testWidgets('đọc log trực tiếp theo từng lượt, dừng khi xong', (
    tester,
  ) async {
    var tails = 0;
    final froms = <Object?>[];
    final env = await _pump(tester, (op, args) {
      if (op == 'jobs.list') return _listJob('running');
      if (op == 'jobs.tail') {
        tails++;
        froms.add(args['from']);
        return tails == 1
            ? {
                'text': 'dòng 1\n',
                'next': 7,
                'done': false,
                'status': 'running',
              }
            : {
                'text': 'dòng 2\n',
                'next': 14,
                'done': true,
                'status': 'finished',
              };
      }
      return <String, Object?>{};
    });
    await _poll(tester);
    final log = tester.widget<SelectableText>(
      find.byKey(const Key('ide_job_log')),
    );
    expect(log.data, 'dòng 1\ndòng 2\n');
    expect(froms.take(2).toList(), [0, 7]);
    expect(find.text('Xong'), findsOneWidget);
    // Đã xong thì không hỏi thêm.
    final n = env.calls.where((c) => c == 'jobs.tail').length;
    await _poll(tester);
    expect(env.calls.where((c) => c == 'jobs.tail').length, n);
    expect(find.byKey(const Key('ide_job_cancel')), findsNothing);
    await _finish(tester);
  });

  testWidgets('huỷ việc: hỏi xác nhận rồi gọi jobs.cancel', (tester) async {
    final env = await _pump(tester, (op, args) {
      if (op == 'jobs.list') return _listJob('running');
      if (op == 'jobs.tail') {
        return {
          'text': 'đang chạy\n',
          'next': 1,
          'done': false,
          'status': 'running',
        };
      }
      return <String, Object?>{};
    });
    await tester.tap(find.byKey(const Key('ide_job_cancel')));
    await tester.pumpAndSettle();
    expect(find.text('Huỷ việc này?'), findsOneWidget);

    await tester.tap(find.byKey(const Key('webtui_dialog_cancel')));
    await tester.pumpAndSettle();
    expect(env.calls.contains('jobs.cancel'), isFalse);

    await tester.tap(find.byKey(const Key('ide_job_cancel')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('webtui_dialog_confirm')));
    await tester.pump();
    await settle(tester);
    final cancel = env.lastSocket!
        .sentOfType('op')
        .firstWhere((f) => f['op'] == 'jobs.cancel');
    expect((cancel['args']! as Map)['job'], 'j1');
    await _finish(tester);
  });

  testWidgets('không tìm thấy việc', (tester) async {
    await _pump(tester, (op, _) {
      if (op == 'jobs.list') return {'items': <Object?>[]};
      return const IdeFakeError('not_found');
    });
    expect(find.text('Không tìm thấy việc này'), findsOneWidget);
  });

  testWidgets('không có quyền', (tester) async {
    await _pump(tester, (_, _) => const IdeFakeError('forbidden'));
    expect(find.text('Không có quyền'), findsOneWidget);
  });

  testWidgets('việc xong không có log', (tester) async {
    await _pump(tester, (op, _) {
      if (op == 'jobs.list') return _listJob('finished');
      return {'text': '', 'next': 0, 'done': true, 'status': 'finished'};
    });
    expect(find.text('Việc này không có log.'), findsOneWidget);
    await _finish(tester);
  });
}

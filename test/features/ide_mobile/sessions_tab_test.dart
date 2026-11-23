import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:webtui_chat/app/providers/foundation_providers.dart';
import 'package:webtui_chat/design_system/theme/webtui_theme.dart';
import 'package:webtui_chat/design_system/tokens/webtui_colors.dart';
import 'package:webtui_chat/features/ide_mobile/data/ide_connection.dart';
import 'package:webtui_chat/features/ide_mobile/presentation/controllers/ide_controllers.dart';
import 'package:webtui_chat/features/ide_mobile/presentation/screens/ide_ai_sessions_tab.dart';
import 'package:webtui_chat/features/ide_mobile/presentation/widgets/ai/ide_new_session_sheet.dart';

import 'support/rpc_env.dart';

final _now = DateTime.now().toUtc();

Map<String, Object?> _session(
  String key,
  String project,
  String status, {
  String title = '',
  String worktree = '',
}) => {
  'session_key': key,
  'kind': 'claude',
  'root': '/srv/$project',
  'project': project,
  'worktree': worktree,
  'title': title,
  'status': status,
  'updated_at': _now.subtract(const Duration(minutes: 5)).toIso8601String(),
};

Future<IdeRpcEnv> _pump(
  WidgetTester tester,
  IdeFakeHandler handler, {
  IdeLinkPhase phase = IdeLinkPhase.ready,
  List<String>? pushed,
}) async {
  WebTuiColors.apply(Brightness.light);
  final env = IdeRpcEnv(handler);
  addTearDown(() => tester.runAsync(env.dispose));
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const Scaffold(body: IdeAiSessionsTab()),
      ),
      GoRoute(
        path: '/ide/ai/:key',
        builder: (_, state) {
          pushed?.add(state.uri.path);
          return const Scaffold(body: Text('phiên mở'));
        },
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ideRpcClientProvider.overrideWithValue(env.rpc),
        ideLinkStatusProvider.overrideWith(
          (ref) => Stream.value(IdeLinkStatus(phase)),
        ),
      ],
      child: MaterialApp.router(
        theme: WebTuiTheme.light(),
        routerConfig: router,
      ),
    ),
  );
  await tester.runAsync(env.up);
  await settle(tester);
  return env;
}

void main() {
  test('trạng thái phiên và nhãn', () {
    expect(ideSessionState('running'), IdeSessionState.running);
    expect(ideSessionState('waiting'), isNot(IdeSessionState.running));
    expect(
      ideSessionStateLabel(IdeSessionState.running, 'running'),
      'Đang làm',
    );
    expect(ideSessionStateLabel(IdeSessionState.done, 'idle'), isNotEmpty);
    expect(ideTimeAgo(null), isA<String>());
  });

  test('gộp theo dự án giữ thứ tự xuất hiện', () {
    final groups = ideGroupByProject([
      for (final m in [
        _session('a', 'x', 'idle'),
        _session('b', 'y', 'idle'),
        _session('c', 'x', 'idle'),
      ])
        IdeAiSessionItemTestHelper.parse(m),
    ]);
    expect(groups.keys.toList(), ['x', 'y']);
    expect(groups['x']!.map((e) => e.key), ['a', 'c']);
  });

  test('đường dẫn phiên mới được mã hoá', () {
    final loc = ideNewSessionLocation(
      kind: 'claude',
      root: '/srv/dự án&1',
      worktree: null,
    );
    final uri = Uri.parse(loc);
    expect(uri.path, '/ide/ai/new');
    expect(uri.queryParameters['root'], '/srv/dự án&1');
    expect(uri.queryParameters['kind'], 'claude');
    expect(uri.queryParameters.containsKey('worktree'), isFalse);
    final nw = Uri.parse(
      ideNewSessionLocation(kind: 'codex', root: '/r', worktree: 'new'),
    );
    expect(nw.queryParameters['worktree'], 'new');
  });

  testWidgets('hiện phiên theo dự án kèm nhãn trạng thái', (tester) async {
    await _pump(
      tester,
      (op, _) => op == 'ai.sessions'
          ? {
              'items': [
                _session('k1', 'web', 'running', title: 'Sửa lỗi đăng nhập'),
                _session('k2', 'web', 'waiting', title: 'Duyệt kế hoạch'),
                _session('k3', 'app', 'idle', title: 'Xong rồi'),
              ],
            }
          : <String, Object?>{},
    );
    expect(find.text('Sửa lỗi đăng nhập'), findsOneWidget);
    expect(find.text('web'), findsWidgets);
    expect(find.text('app'), findsWidgets);
    expect(find.text('Đang làm'), findsOneWidget);
    expect(find.text('Phiên mới'), findsOneWidget);
  });

  testWidgets('chưa nối IDE: báo chưa nối, không có nút phiên mới', (
    tester,
  ) async {
    await _pump(
      tester,
      (_, _) => {'items': <Object?>[]},
      phase: IdeLinkPhase.connecting,
    );
    expect(find.text('Chưa nối IDE'), findsOneWidget);
    expect(find.text('Phiên mới'), findsNothing);
  });

  testWidgets('danh sách rỗng', (tester) async {
    await _pump(tester, (_, _) => {'items': <Object?>[]});
    expect(find.text('Chưa có phiên AI'), findsOneWidget);
  });

  testWidgets('không có quyền', (tester) async {
    await _pump(tester, (_, _) => const IdeFakeError('forbidden'));
    expect(find.text('Không có quyền'), findsOneWidget);
  });

  testWidgets('lỗi khác: hiện lỗi và nút thử lại', (tester) async {
    await _pump(tester, (_, _) => const IdeFakeError('internal'));
    expect(find.text('Không tải được phiên AI'), findsOneWidget);
  });

  testWidgets('chạm mở phiên, khoá được mã hoá trong đường dẫn', (
    tester,
  ) async {
    final pushed = <String>[];
    await _pump(
      tester,
      (_, _) => {
        'items': [_session('a/b c', 'web', 'idle', title: 'Phiên A')],
      },
      pushed: pushed,
    );
    await tester.tap(find.text('Phiên A'));
    await tester.pumpAndSettle();
    expect(find.text('phiên mở'), findsOneWidget);
    expect(pushed.single, '/ide/ai/a%2Fb%20c');
  });

  testWidgets('giữ lâu hỏi rồi dừng phiên', (tester) async {
    final env = await _pump(
      tester,
      (op, _) => op == 'ai.sessions'
          ? {
              'items': [_session('k1', 'web', 'running', title: 'Phiên chạy')],
            }
          : <String, Object?>{},
    );
    await tester.longPress(find.text('Phiên chạy'));
    await tester.pumpAndSettle();
    expect(find.text('Dừng phiên này?'), findsOneWidget);

    // Bấm "Giữ lại"/huỷ: không gọi dừng.
    await tester.tap(find.byKey(const Key('webtui_dialog_cancel')));
    await tester.pumpAndSettle();
    expect(env.calls.contains('ai.sessions_stop'), isFalse);

    await tester.longPress(find.text('Phiên chạy'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('webtui_dialog_confirm')));
    await tester.pump();
    await settle(tester);
    expect(env.calls.contains('ai.sessions_stop'), isTrue);
    final stop = env.lastSocket!
        .sentOfType('op')
        .firstWhere((f) => f['op'] == 'ai.sessions_stop');
    expect((stop['args']! as Map)['session_key'], 'k1');
    await tester.pump(const Duration(seconds: 5));
  });
}

/// Dựng một mục phiên từ bản ghi thô (qua bộ phân tích thật).
abstract final class IdeAiSessionItemTestHelper {
  static IdeAiSessionItem parse(Map<String, Object?> m) =>
      IdeAiSessionItem.tryParse(m)!;
}

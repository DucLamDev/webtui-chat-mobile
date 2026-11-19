import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/app/providers/foundation_providers.dart';
import 'package:webtui_chat/design_system/theme/webtui_theme.dart';
import 'package:webtui_chat/design_system/tokens/webtui_colors.dart';
import 'package:webtui_chat/features/ide_mobile/data/ide_connection.dart';
import 'package:webtui_chat/features/ide_mobile/domain/ide_device_security.dart';
import 'package:webtui_chat/features/ide_mobile/domain/ide_ready.dart';
import 'package:webtui_chat/features/ide_mobile/domain/ide_term.dart';
import 'package:webtui_chat/features/ide_mobile/presentation/controllers/ide_controllers.dart';
import 'package:webtui_chat/features/ide_mobile/presentation/screens/terminal/ide_terminal_screen.dart';
import 'package:webtui_chat/features/ide_mobile/presentation/screens/terminal/ide_terminal_tab.dart';

import 'package:xterm/xterm.dart' show TerminalView;

import 'support/fakes.dart';
import 'support/rpc_env.dart';

const _ops = [
  'ai.sessions',
  'term.list',
  'term.kill',
  'term.targets',
  'projects.list',
];

Map<String, Object?> _item(
  String name, {
  bool attached = false,
  String cmd = 'shell',
}) => {
  'name': name,
  'root': '/srv/du-an-$name',
  'cmd': cmd,
  'attached': attached,
};

final class _Ctx {
  _Ctx(this.env, this.security);
  final IdeRpcEnv env;
  final FakeIdeSecurity security;
}

Future<_Ctx> _pumpTab(
  WidgetTester tester,
  IdeFakeHandler handler, {
  Map<String, bool> features = const {},
  FakeIdeSecurity? security,
  Brightness brightness = Brightness.light,
}) async {
  WebTuiColors.apply(brightness);
  final env = IdeRpcEnv(handler, ops: _ops);
  final sec = security ?? FakeIdeSecurity();
  addTearDown(() => tester.runAsync(env.dispose));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ideRpcClientProvider.overrideWithValue(env.rpc),
        ideConnectionProvider.overrideWithValue(env.connection),
        ideDeviceSecurityProvider.overrideWithValue(sec),
        ideLinkStatusProvider.overrideWith(
          (ref) => Stream.value(
            IdeLinkStatus(
              IdeLinkPhase.ready,
              ready: IdeReady(ops: _ops.toSet(), features: features),
            ),
          ),
        ),
      ],
      child: MaterialApp(
        theme: WebTuiTheme.light(),
        home: const Scaffold(body: IdeTerminalTab()),
      ),
    ),
  );
  await tester.runAsync(env.up);
  await settle(tester);
  return _Ctx(env, sec);
}

void main() {
  testWidgets('danh sách: tên, dự án, kiểu, máy khác đang gắn', (tester) async {
    await _pumpTab(
      tester,
      (op, args) => op == 'term.list'
          ? {
              'items': [
                _item('a', attached: true, cmd: 'claude'),
                _item('b', cmd: 'ssh:h1'),
              ],
            }
          : <String, Object?>{},
    );
    expect(find.text('a'), findsOneWidget);
    expect(find.textContaining('du-an-a'), findsOneWidget);
    expect(find.textContaining('Claude'), findsOneWidget);
    expect(find.text('Máy khác đang gắn'), findsOneWidget);
    expect(find.textContaining('SSH: h1'), findsOneWidget);
    expect(find.text('Terminal mới'), findsOneWidget);
  });

  testWidgets('danh sách rỗng và lỗi có thử lại', (tester) async {
    await _pumpTab(tester, (op, args) => {'items': <Object?>[]});
    expect(find.text('Chưa có terminal'), findsOneWidget);
  });

  testWidgets('lỗi tải hiện nút thử lại', (tester) async {
    await _pumpTab(
      tester,
      (op, args) => op == 'term.list' ? const IdeFakeError('internal') : {},
    );
    expect(find.text('Không tải được terminal'), findsOneWidget);
  });

  testWidgets('features.terminal=false: ẩn nội dung, báo quản trị đã tắt', (
    tester,
  ) async {
    final ctx = await _pumpTab(
      tester,
      (op, args) => {
        'items': [_item('a')],
      },
      features: {'terminal': false},
    );
    expect(find.byKey(const Key('term_disabled')), findsOneWidget);
    expect(
      find.text('Quản trị đã tắt terminal trên điện thoại.'),
      findsOneWidget,
    );
    expect(find.text('a'), findsNothing);
    expect(find.text('Terminal mới'), findsNothing);
    expect(ctx.env.calls.where((c) => c.startsWith('term.')), isEmpty);
  });

  testWidgets('term.list báo forbidden: cũng ẩn và báo đã tắt', (tester) async {
    await _pumpTab(
      tester,
      (op, args) => op == 'term.list' ? const IdeFakeError('forbidden') : {},
    );
    expect(find.byKey(const Key('term_disabled')), findsOneWidget);
  });

  testWidgets('nhấn giữ -> hỏi lại -> term.kill rồi tải lại danh sách', (
    tester,
  ) async {
    var killed = false;
    final ctx = await _pumpTab(tester, (op, args) {
      if (op == 'term.kill') {
        killed = args['name'] == 'a';
        return {'ok': true};
      }
      return {
        'items': [if (!killed) _item('a'), _item('b')],
      };
    });
    await tester.longPress(find.text('a'));
    await tester.pumpAndSettle();
    expect(find.text('Kết thúc phiên này?'), findsOneWidget);
    // Huỷ thì không giết.
    await tester.tap(find.text('Huỷ'));
    await tester.pumpAndSettle();
    expect(ctx.env.calls, isNot(contains('term.kill')));
    await tester.longPress(find.text('a'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kết thúc phiên'));
    await tester.pump();
    await settle(tester, 4);
    expect(ctx.env.calls, contains('term.kill'));
    expect(find.text('a'), findsNothing);
    expect(find.text('b'), findsOneWidget);
  });

  testWidgets('vân tay huỷ thì không mở terminal', (tester) async {
    final sec = FakeIdeSecurity(auth: DeviceOwnerAuthResult.cancelled);
    final ctx = await _pumpTab(
      tester,
      (op, args) => {
        'items': [_item('a')],
      },
      security: sec,
    );
    await tester.tap(find.text('a'));
    await settle(tester);
    expect(sec.authCalls, 1);
    expect(find.byType(IdeTerminalScreen), findsNothing);
    expect(ctx.env.lastSocket!.sentOfType('term'), isEmpty);
  });

  testWidgets('máy chưa đặt vân tay: báo, không mở', (tester) async {
    final sec = FakeIdeSecurity(auth: DeviceOwnerAuthResult.notEnrolled);
    await _pumpTab(
      tester,
      (op, args) => {
        'items': [_item('a')],
      },
      security: sec,
    );
    await tester.tap(find.text('a'));
    await settle(tester);
    expect(find.byType(IdeTerminalScreen), findsNothing);
    expect(find.textContaining('vân tay'), findsOneWidget);
  });

  testWidgets('vân tay đạt thì mở màn terminal và gắn bằng name', (
    tester,
  ) async {
    final sec = FakeIdeSecurity();
    final ctx = await _pumpTab(
      tester,
      (op, args) => {
        'items': [_item('a')],
      },
      security: sec,
    );
    await tester.tap(find.text('a'));
    await settle(tester);
    expect(sec.authCalls, 1);
    expect(find.byType(IdeTerminalScreen), findsOneWidget);
    final term = ctx.env.lastSocket!.sentOfType('term').single;
    expect(term, {'type': 'term', 'name': 'a'});
  });

  testWidgets('Terminal mới: chọn dự án + SSH máy của tôi -> new{root,cmd}', (
    tester,
  ) async {
    final ctx = await _pumpTab(tester, (op, args) {
      return switch (op) {
        'projects.list' => {
          'items': [
            {'name': 'DuAn', 'root': '/srv/duan', 'git': true},
          ],
        },
        'term.targets' => {
          'ssh': [
            {'alias': 'g1', 'label': 'Máy cấp'},
          ],
          'my_ssh': [
            {'alias': 'm1', 'label': 'Máy tôi'},
          ],
        },
        _ => {'items': <Object?>[]},
      };
    });
    await tester.tap(find.byKey(const Key('term_new')));
    await tester.pumpAndSettle();
    await settle(tester);
    expect(find.text('SSH máy được cấp'), findsOneWidget);
    expect(find.text('SSH máy của tôi'), findsOneWidget);
    await tester.tap(find.text('SSH máy của tôi'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('term_new_host')), findsOneWidget);
    await tester.tap(find.byKey(const Key('term_new_start')));
    await settle(tester);
    expect(ctx.security.authCalls, 1);
    expect(ctx.env.lastSocket!.sentOfType('term').single, {
      'type': 'term',
      'new': {'root': '/srv/duan', 'cmd': 'my-ssh:m1', 'cols': 80, 'rows': 24},
    });
  });

  group('màn terminal', () {
    Future<(IdeRpcEnv, AutoIdeSocket)> pumpScreen(
      WidgetTester tester, {
      Brightness brightness = Brightness.light,
      IdeTermOpenTarget target = const IdeTermOpenTarget.existing('a'),
    }) async {
      WebTuiColors.apply(brightness);
      final env = IdeRpcEnv((op, args) => {}, ops: _ops);
      addTearDown(() => tester.runAsync(env.dispose));
      await tester.runAsync(env.up);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [ideConnectionProvider.overrideWithValue(env.connection)],
          child: MaterialApp(
            theme: WebTuiTheme.light(),
            home: IdeTerminalScreen(target: target),
          ),
        ),
      );
      await settle(tester);
      return (env, env.lastSocket!);
    }

    String typed(AutoIdeSocket s) => utf8.decode([
      for (final f in s.sentOfType('tin'))
        ...base64Decode(f['data']! as String),
    ]);

    testWidgets('tready, phím phụ gửi tin, texit hiện mã', (tester) async {
      final (_, socket) = await pumpScreen(tester);
      socket.emit({'type': 'tready', 'name': 'a', 'cols': 80, 'rows': 24});
      socket.emit({
        'type': 'tout',
        'data': base64Encode(utf8.encode('Chào\r\n')),
      });
      await settle(tester);
      // Ctrl dính rồi c = 0x03.
      await tester.tap(find.byKey(const Key('term_key_ctrl')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('term_key_esc')));
      await tester.tap(find.byKey(const Key('term_key_up')));
      await tester.tap(find.byKey(const Key('term_key_pipe')));
      await tester.tap(find.byKey(const Key('term_key_tab')));
      await tester.drag(
        find.byKey(const Key('term_key_tab')),
        const Offset(-700, 0),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('term_key_pgup')));
      await settle(tester);
      expect(typed(socket), '\x1b\x1b[A|\t\x1b[5~');
      socket.emit({'type': 'texit', 'code': 7});
      await settle(tester);
      expect(find.text('Phiên đã kết thúc (mã 7)'), findsOneWidget);
      expect(find.byKey(const Key('term_key_esc')), findsNothing);
    });

    testWidgets('forbidden: ẩn terminal, báo quản trị đã tắt', (tester) async {
      final (_, socket) = await pumpScreen(tester);
      socket.emit({'type': 'error', 'code': 'forbidden', 'message': 'x'});
      await settle(tester);
      expect(
        find.text('Quản trị đã tắt terminal trên điện thoại.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('term_view')), findsNothing);
    });

    testWidgets('busy: báo quá số terminal', (tester) async {
      final (_, socket) = await pumpScreen(tester);
      socket.emit({'type': 'error', 'code': 'busy', 'message': 'x'});
      await settle(tester);
      expect(find.text('Đã mở quá số terminal cho phép'), findsOneWidget);
    });

    testWidgets('not_found: gắn lại báo phiên không còn, mở mới báo chọn lại', (
      tester,
    ) async {
      var (_, socket) = await pumpScreen(tester);
      socket.emit({'type': 'error', 'code': 'not_found', 'message': 'x'});
      await settle(tester);
      expect(find.text('Phiên này không còn'), findsOneWidget);

      (_, socket) = await pumpScreen(
        tester,
        target: const IdeTermOpenTarget.create(root: '/srv/mat', cmd: 'shell'),
      );
      socket.emit({'type': 'error', 'code': 'not_found', 'message': 'x'});
      await settle(tester);
      expect(
        find.text('Không tìm thấy dự án hoặc máy chủ đã chọn'),
        findsOneWidget,
      );
      expect(find.text('Phiên này không còn'), findsNothing);
    });

    testWidgets('mất kết nối: nút Nối lại gắn lại bằng name', (tester) async {
      final (env, socket) = await pumpScreen(tester);
      socket.emit({'type': 'tready', 'name': 'a', 'cols': 80, 'rows': 24});
      await settle(tester);
      await tester.runAsync(() async {
        await socket.close();
      });
      await settle(tester);
      expect(find.byKey(const Key('term_reconnect')), findsOneWidget);
      await tester.tap(find.byKey(const Key('term_reconnect')));
      await settle(tester);
      final again = env.lastSocket!;
      expect(identical(again, socket), isFalse);
      expect(again.sentOfType('term').single, {'type': 'term', 'name': 'a'});
    });

    testWidgets('dán nhiều dòng phải hỏi lại; huỷ thì không gửi', (
      tester,
    ) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async => call.method == 'Clipboard.getData'
            ? {'text': 'ls\nrm -rf x\n'}
            : null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final (_, socket) = await pumpScreen(tester);
      socket.emit({'type': 'tready', 'name': 'a', 'cols': 80, 'rows': 24});
      await settle(tester);
      await tester.tap(find.byKey(const Key('term_paste')));
      await tester.pumpAndSettle();
      expect(find.text('Dán nhiều dòng?'), findsOneWidget);
      await tester.tap(find.text('Huỷ'));
      await tester.pumpAndSettle();
      await settle(tester);
      expect(typed(socket), isEmpty);
      await tester.tap(find.byKey(const Key('term_paste')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dán'));
      await tester.pumpAndSettle();
      await settle(tester);
      expect(typed(socket), 'ls\nrm -rf x\n');
    });

    testWidgets('chụm 2 ngón đổi cỡ chữ trong giới hạn', (tester) async {
      final (_, socket) = await pumpScreen(tester);
      socket.emit({'type': 'tready', 'name': 'a', 'cols': 80, 'rows': 24});
      await settle(tester);
      double size() => tester
          .widget<TerminalView>(find.byKey(const Key('term_view')))
          .textStyle
          .fontSize;
      expect(size(), 13);
      final c = tester.getCenter(find.byKey(const Key('term_view')));
      final g1 = await tester.startGesture(c - const Offset(40, 0), pointer: 1);
      final g2 = await tester.startGesture(c + const Offset(40, 0), pointer: 2);
      await g1.moveBy(const Offset(-40, 0));
      await g2.moveBy(const Offset(40, 0));
      await tester.pump();
      expect(size(), greaterThan(13));
      await g1.moveBy(const Offset(-2000, 0));
      await tester.pump();
      expect(size(), lessThanOrEqualTo(28));
      await g1.up();
      await g2.up();
    });
  });
}

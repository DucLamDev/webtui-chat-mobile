import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/ide_mobile/presentation/screens/tools/ide_demo_screen.dart';

import 'tools_env.dart';

const _ops = {
  'demo.status',
  'demo.enable',
  'demo.set',
  'demo.disable',
  'demo.update',
  'demo.db_create',
  'demo.db_show',
  'demo.db_drop',
  'demo.log',
};

const _secret = 'S3cretPw-Zq81';

Map<String, Object?> _status({bool enabled = true, bool manage = true}) => {
  'my': false,
  'can_manage': manage,
  'mode': 'github',
  'domain': 'web.demo.example.com',
  'demo': {
    'enabled': enabled,
    'exists': enabled,
    'root': '/var/www/web',
    'branch': 'main',
    'url': 'https://web.demo.example.com',
    'db': enabled,
    'db_name': 'web_demo',
  },
};

Object? _handler(String op, Map<String, Object?> a) => switch (op) {
  'demo.status' => _status(),
  'demo.db_show' => {
    'db': {
      'host': '127.0.0.1',
      'port': 3306,
      'database': 'web_demo',
      'username': 'web_demo',
    },
    'password': _secret,
  },
  'demo.log' => {'text': 'dòng log 1'},
  _ => {},
};

void main() {
  testWidgets('tải được trạng thái, có nút theo op', (t) async {
    await pumpTool(t, const IdeDemoScreen(project: 'web'), _handler, ops: _ops);
    expect(find.byKey(const Key('ide_demo_view')), findsOneWidget);
    expect(find.byKey(const Key('ide_demo_disable')), findsOneWidget);
    expect(find.byKey(const Key('ide_demo_db_show')), findsOneWidget);
  });

  testWidgets('op không có thì ẩn nút', (t) async {
    await pumpTool(
      t,
      const IdeDemoScreen(project: 'web'),
      _handler,
      ops: _ops.difference({'demo.disable', 'demo.db_show', 'demo.db_drop'}),
    );
    expect(find.byKey(const Key('ide_demo_disable')), findsNothing);
    expect(find.byKey(const Key('ide_demo_db_show')), findsNothing);
    expect(find.byKey(const Key('ide_demo_db_drop')), findsNothing);
  });

  testWidgets('không có quyền quản lý thì ẩn mọi nút thao tác', (t) async {
    await pumpTool(
      t,
      const IdeDemoScreen(project: 'web'),
      (op, a) => op == 'demo.status' ? _status(manage: false) : _handler(op, a),
      ops: _ops,
    );
    expect(find.byKey(const Key('ide_demo_disable')), findsNothing);
    expect(find.byKey(const Key('ide_demo_set')), findsNothing);
    expect(find.byKey(const Key('ide_demo_db_create')), findsNothing);
  });

  testWidgets('lỗi có nút thử lại; forbidden không có', (t) async {
    await pumpTool(
      t,
      const IdeDemoScreen(project: 'web'),
      (op, a) => const IdeFakeError('internal'),
      ops: _ops,
    );
    expect(find.text('Thử lại'), findsOneWidget);
  });

  testWidgets('forbidden: báo không có quyền', (t) async {
    await pumpTool(
      t,
      const IdeDemoScreen(project: 'web'),
      (op, a) => const IdeFakeError('forbidden'),
      ops: _ops,
    );
    expect(find.byKey(const Key('ide_demo_view')), findsNothing);
    expect(find.text('Thử lại'), findsNothing);
  });

  testWidgets('mật khẩu DB chỉ có trong hộp thoại, đóng là mất', (t) async {
    await pumpTool(t, const IdeDemoScreen(project: 'web'), _handler, ops: _ops);
    final btn = find.byKey(const Key('ide_demo_db_show'));
    await t.ensureVisible(btn);
    await t.tap(btn);
    await settle(t);
    expect(find.byKey(const Key('ide_db_password')), findsOneWidget);
    // Mặc định che.
    expect(find.textContaining(_secret), findsNothing);
    expect(find.textContaining('một lần'), findsOneWidget);
    await t.tap(find.byTooltip('Hiện'));
    await t.pump();
    expect(find.textContaining(_secret), findsOneWidget);
    await t.tap(find.byKey(const Key('ide_db_close')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('ide_db_password')), findsNothing);
    expect(find.textContaining(_secret), findsNothing);
    // Mở lại phải hỏi máy lại, không dùng bản cũ.
    // (db_show đã gọi đúng một lần)
  });

  testWidgets('bật demo: cấu hình rồi mở màn việc nền', (t) async {
    final pushed = <String>[];
    final env = await pumpTool(
      t,
      const IdeDemoScreen(project: 'web'),
      (op, a) => switch (op) {
        'demo.status' => _status(enabled: false),
        'demo.enable' => {'job': 'j1'},
        _ => {},
      },
      ops: _ops,
      pushed: pushed,
    );
    await t.tap(find.byKey(const Key('ide_demo_enable')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('ide_demo_root')), 'public');
    await t.pump();
    final ok = find.byKey(const Key('ide_demo_config_ok'));
    await t.ensureVisible(ok);
    await t.tap(ok);
    await settle(t);
    final sent = sentOps(env, 'demo.enable');
    expect(sent, hasLength(1));
    expect(sent.single['root'], 'public');
    expect(pushed, ['/ide/jobs/j1']);
  });

  testWidgets('đường dẫn gốc có ../ bị chặn, không gửi', (t) async {
    final env = await pumpTool(
      t,
      const IdeDemoScreen(project: 'web'),
      (op, a) => op == 'demo.status' ? _status(enabled: false) : {},
      ops: _ops,
    );
    await t.tap(find.byKey(const Key('ide_demo_enable')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('ide_demo_root')), 'a/../etc');
    await t.pump();
    final ok = find.byKey(const Key('ide_demo_config_ok'));
    await t.ensureVisible(ok);
    await t.tap(ok, warnIfMissed: false);
    await settle(t);
    expect(sentOps(env, 'demo.enable'), isEmpty);
  });

  testWidgets('tắt demo là ★: hỏi lại, rồi need_step', (t) async {
    var steps = 0;
    final env = await pumpTool(
      t,
      const IdeDemoScreen(project: 'web'),
      (op, a) => op == 'demo.disable' ? ideFakeSilent : _handler(op, a),
      ops: _ops,
      step: (r) async {
        steps++;
        return 'chu-ky';
      },
    );
    final btn = find.byKey(const Key('ide_demo_disable'));
    await t.ensureVisible(btn);
    await t.tap(btn);
    await settle(t);
    expect(sentOps(env, 'demo.disable'), isEmpty);
    await t.tap(find.text('Tắt').last);
    await settle(t);
    expect(sentOps(env, 'demo.disable'), hasLength(1));
    final req = await emitNeedStep(t, env);
    expect(steps, 1);
    env.lastSocket!.emit({
      'type': 'result',
      'req': req,
      'ok': true,
      'data': {},
    });
    await settle(t);
  });
}

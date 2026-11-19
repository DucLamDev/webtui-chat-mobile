import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/ide_mobile/presentation/screens/tools/ide_servers_screen.dart';

import 'tools_env.dart';

const _ops = {
  'servers.list',
  'servers.key',
  'servers.check',
  'servers.add',
  'servers.edit',
  'servers.remove',
};

const _pw = 'Mk-Rieng-9981';

Map<String, Object?> _list() => {
  'items': [
    {
      'name': 'vps-a',
      'host': '203.0.113.5',
      'port': 22,
      'user': 'root',
      'label': 'Máy A',
      'key_ok': true,
      'projects': ['web'],
    },
  ],
};

IdeFakeHandler _h({Map<String, Object?>? extra}) => (op, a) {
  if (extra != null && extra.containsKey(op)) return extra[op];
  return switch (op) {
    'servers.list' => _list(),
    'servers.key' => {'pubkey': 'ssh-ed25519 AAAAC3Nza chat-hub'},
    _ => {},
  };
};

Future<void> _openAdd(WidgetTester t) async {
  await t.tap(find.byKey(const Key('ide_servers_add')));
  await settleAll(t);
}

Future<void> _fillAdd(
  WidgetTester t, {
  String port = '22',
  String pw = _pw,
}) async {
  await t.enterText(find.byKey(const Key('ide_server_f_host')), '198.51.100.7');
  await t.enterText(find.byKey(const Key('ide_server_f_port')), port);
  if (pw.isNotEmpty) {
    await t.enterText(find.byKey(const Key('ide_server_f_password')), pw);
  }
  await t.pump();
}

void main() {
  testWidgets('tải được danh sách', (t) async {
    await pumpTool(t, const IdeServersScreen(), _h(), ops: _ops);
    expect(find.byKey(const Key('ide_server_vps-a')), findsOneWidget);
    expect(find.byKey(const Key('ide_server_check_vps-a')), findsOneWidget);
    expect(find.byKey(const Key('ide_servers_add')), findsOneWidget);
  });

  testWidgets('rỗng', (t) async {
    await pumpTool(
      t,
      const IdeServersScreen(),
      (op, a) => op == 'servers.list' ? {'items': []} : {},
      ops: _ops,
    );
    expect(find.text('Chưa có máy chủ nào'), findsOneWidget);
  });

  testWidgets('lỗi có nút thử lại', (t) async {
    await pumpTool(
      t,
      const IdeServersScreen(),
      (op, a) => const IdeFakeError('internal'),
      ops: _ops,
    );
    expect(find.text('Thử lại'), findsOneWidget);
  });

  testWidgets('forbidden không có nút thử lại', (t) async {
    await pumpTool(
      t,
      const IdeServersScreen(),
      (op, a) => const IdeFakeError('forbidden'),
      ops: _ops,
    );
    expect(find.byKey(const Key('ide_server_vps-a')), findsNothing);
    expect(find.text('Thử lại'), findsNothing);
  });

  testWidgets('op không có trong ready.ops thì ẩn nút', (t) async {
    await pumpTool(t, const IdeServersScreen(), _h(), ops: {'servers.list'});
    expect(find.byKey(const Key('ide_server_vps-a')), findsOneWidget);
    expect(find.byKey(const Key('ide_server_check_vps-a')), findsNothing);
    expect(find.byKey(const Key('ide_server_edit_vps-a')), findsNothing);
    expect(find.byKey(const Key('ide_server_remove_vps-a')), findsNothing);
    expect(find.byKey(const Key('ide_servers_add')), findsNothing);
    expect(find.byKey(const Key('ide_servers_key')), findsNothing);
  });

  testWidgets('xem khoá công khai và chép', (t) async {
    await pumpTool(t, const IdeServersScreen(), _h(), ops: _ops);
    await t.tap(find.byKey(const Key('ide_servers_key')));
    await settleAll(t);
    expect(find.textContaining('ssh-ed25519'), findsOneWidget);
    expect(find.byKey(const Key('ide_server_pubkey_copy')), findsOneWidget);
  });

  testWidgets('thêm: ô mật khẩu ẩn ký tự, xoá ngay khi gửi, chặn bấm đôi', (
    t,
  ) async {
    final env = await pumpTool(
      t,
      const IdeServersScreen(),
      _h(extra: {'servers.add': ideFakeSilent}),
      ops: _ops,
    );
    await _openAdd(t);
    final pwField = t.widget<TextField>(
      find.byKey(const Key('ide_server_f_password')),
    );
    expect(pwField.obscureText, isTrue);
    await _fillAdd(t);
    final submit = find.byKey(const Key('ide_server_submit'));
    await t.ensureVisible(submit);
    await t.tap(submit);
    await t.pump();
    await t.tap(submit, warnIfMissed: false);
    await settle(t);
    final sent = sentOps(env, 'servers.add');
    expect(sent, hasLength(1));
    expect(sent.single['password'], _pw);
    expect(sent.single['host'], '198.51.100.7');
    expect(sent.single.containsKey('lock_ssh'), isFalse);
    // Mật khẩu đã bị xoá khỏi ô nhập ngay sau khi gửi.
    expect(
      t
          .widget<TextField>(find.byKey(const Key('ide_server_f_password')))
          .controller!
          .text,
      isEmpty,
    );
    final req = await emitNeedStep(t, env);
    env.lastSocket!.emit({
      'type': 'result',
      'req': req,
      'ok': true,
      'data': {},
    });
    await settleAll(t);
  });

  testWidgets('thêm là ★: đi qua need_step rồi đóng sheet', (t) async {
    var steps = 0;
    final env = await pumpTool(
      t,
      const IdeServersScreen(),
      _h(extra: {'servers.add': ideFakeSilent}),
      ops: _ops,
      step: (r) async {
        steps++;
        expect(r.op, 'servers.add');
        return 'chu-ky';
      },
    );
    await _openAdd(t);
    await _fillAdd(t);
    final submit = find.byKey(const Key('ide_server_submit'));
    await t.ensureVisible(submit);
    await t.tap(submit);
    await settle(t);
    final req = await emitNeedStep(t, env);
    expect(steps, 1);
    env.lastSocket!.emit({
      'type': 'result',
      'req': req,
      'ok': true,
      'data': {},
    });
    await settleAll(t);
    expect(find.byKey(const Key('ide_server_submit')), findsNothing);
  });

  testWidgets('cổng sai thì không gửi', (t) async {
    final env = await pumpTool(t, const IdeServersScreen(), _h(), ops: _ops);
    await _openAdd(t);
    await _fillAdd(t, port: '70000');
    final submit = find.byKey(const Key('ide_server_submit'));
    await t.ensureVisible(submit);
    await t.tap(submit);
    await t.pump();
    expect(sentOps(env, 'servers.add'), isEmpty);
    expect(find.text('Cổng 1–65535'), findsOneWidget);
  });

  testWidgets(
    'lỗi bad_request không mật khẩu: hiện khoá công khai để cài tay',
    (t) async {
      await pumpTool(
        t,
        const IdeServersScreen(),
        _h(
          extra: {
            'servers.add': const IdeFakeError('bad_request', 'chưa vào được'),
          },
        ),
        ops: _ops,
      );
      await _openAdd(t);
      await _fillAdd(t, pw: '');
      final submit = find.byKey(const Key('ide_server_submit'));
      await t.ensureVisible(submit);
      await t.tap(submit);
      await settle(t);
      await settleAll(t);
      expect(find.byKey(const Key('ide_server_error')), findsOneWidget);
      expect(find.byKey(const Key('ide_server_pubkey')), findsOneWidget);
    },
  );

  testWidgets('gỡ: còn dự án dùng thì hỏi lại rồi gửi with_projects', (
    t,
  ) async {
    var first = true;
    final env = await pumpTool(t, const IdeServersScreen(), (op, a) {
      if (op == 'servers.remove') {
        if (first) {
          first = false;
          return const IdeFakeError('conflict', 'còn dự án');
        }
        return {};
      }
      return _h()(op, a);
    }, ops: _ops);
    await t.tap(find.byKey(const Key('ide_server_remove_vps-a')));
    await settleAll(t);
    await t.tap(find.text('Gỡ').last);
    await settle(t);
    expect(find.text('Còn dự án đang dùng'), findsOneWidget);
    await t.tap(find.text('Vẫn gỡ'));
    await settleAll(t);
    final sent = sentOps(env, 'servers.remove');
    expect(sent, hasLength(2));
    expect(sent.first.containsKey('with_projects'), isFalse);
    expect(sent.last['with_projects'], isTrue);
  });

  testWidgets('chữ hệ thống cỡ 1,6 không tràn', (t) async {
    await pumpTool(
      t,
      const IdeServersScreen(),
      _h(),
      ops: _ops,
      textScale: 1.6,
    );
    expect(t.takeException(), isNull);
  });
}

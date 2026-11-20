import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/ide_mobile/application/ide_talk_service.dart';
import 'package:webtui_chat/features/ide_mobile/domain/ide_talk_models.dart';
import 'package:webtui_chat/features/ide_mobile/presentation/screens/talk/ide_talk_composer.dart';
import 'package:webtui_chat/features/ide_mobile/presentation/screens/talk/ide_talk_new_sheet.dart';
import 'package:webtui_chat/features/ide_mobile/presentation/screens/talk/ide_talk_providers.dart';

import '../support/rpc_env.dart';

final _pid = 'a1' * 16;
const _talk = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

Object? _handler(String op, Map<String, Object?> a) => switch (op) {
  'talk.projects' => {
    'items': [
      {'id': _pid, 'name': 'Dự án A', 'instructions': 'x'},
      {'id': 'KHONG-HOP-LE', 'name': 'Xấu'},
    ],
  },
  'talk.send' => {'id': _talk},
  _ => <String, Object?>{},
};

void main() {
  test(
    'talk.projects: bỏ mục sai mã; send gửi project chỉ khi id=new',
    () async {
      final env = IdeRpcEnv(_handler, ops: ['talk.projects', 'talk.send']);
      await env.up();
      final svc = IdeTalkService(env.rpc);
      final list = await svc.projects();
      expect(list.map((p) => p.id), [_pid]);
      await svc.send(id: 'new', text: 'hi', project: _pid);
      await svc.send(id: 'new', text: 'hi', project: 'zz');
      await svc.send(id: _talk, text: 'hi', project: _pid);
      final sent = env.lastSocket!
          .sentOfType('op')
          .where((f) => f['op'] == 'talk.send')
          .map((f) => f['args']! as Map)
          .toList();
      expect(sent[0]['project'], _pid);
      expect(sent[1].containsKey('project'), isFalse);
      expect(sent[2].containsKey('project'), isFalse);
      await env.dispose();
    },
  );

  test('mã dự án Chat: đúng 32 hex thường', () {
    expect(ideTalkChatProjectIdOk(_pid), isTrue);
    expect(ideTalkChatProjectIdOk('A1' * 16), isFalse);
    expect(ideTalkChatProjectIdOk('a1' * 15), isFalse);
  });

  Future<IdeRpcEnv> pumpSheet(WidgetTester t, IdeFakeHandler h) async {
    final env = IdeRpcEnv(h, ops: ['talk.projects', 'talk.send']);
    addTearDown(() => t.runAsync(env.dispose));
    await t.runAsync(env.up);
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          ideTalkServiceProvider.overrideWithValue(IdeTalkService(env.rpc)),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: IdeTalkNewSheet(withModels: false, withProjects: true),
          ),
        ),
      ),
    );
    await settle(t);
    return env;
  }

  testWidgets('hộp chat mới: chọn Dự án Chat thì gửi project', (t) async {
    final env = await pumpSheet(t, _handler);
    expect(find.byKey(const Key('talk_new_project')), findsOneWidget);
    await t.enterText(find.byKey(const Key('talk_new_text')), 'xin chào');
    await t.tap(find.byKey(const Key('talk_new_project')));
    await t.pumpAndSettle();
    await t.tap(find.text('Dự án A').last);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('talk_new_send')));
    await settle(t);
    final f = env.lastSocket!
        .sentOfType('op')
        .firstWhere((f) => f['op'] == 'talk.send');
    expect((f['args']! as Map)['project'], _pid);
  });

  testWidgets('hộp chat mới: mặc định không dự án', (t) async {
    final env = await pumpSheet(t, _handler);
    await t.enterText(find.byKey(const Key('talk_new_text')), 'xin chào');
    await t.tap(find.byKey(const Key('talk_new_send')));
    await settle(t);
    final f = env.lastSocket!
        .sentOfType('op')
        .firstWhere((f) => f['op'] == 'talk.send');
    expect((f['args']! as Map).containsKey('project'), isFalse);
  });

  testWidgets('hộp chat mới: danh sách rỗng thì ẩn ô, vẫn tạo được', (t) async {
    await pumpSheet(
      t,
      (op, a) => op == 'talk.projects'
          ? <String, Object?>{'items': []}
          : _handler(op, a),
    );
    expect(find.byKey(const Key('talk_new_project')), findsNothing);
    expect(find.byKey(const Key('talk_new_send')), findsOneWidget);
  });

  testWidgets('thanh cuộc AI Agent: có nút Chạy ngay khi có op', (t) async {
    var runs = 0;
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(body: IdeTalkAgentBar(onRun: () => runs++)),
      ),
    );
    expect(find.textContaining('Cuộc của AI Agent'), findsOneWidget);
    await t.tap(find.byKey(const Key('talk_agent_run')));
    expect(runs, 1);
    await t.pumpWidget(
      const MaterialApp(home: Scaffold(body: IdeTalkAgentBar(onRun: null))),
    );
    expect(find.byKey(const Key('talk_agent_run')), findsNothing);
  });
}

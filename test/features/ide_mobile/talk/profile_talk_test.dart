import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/ide_mobile/application/ide_avatar_encoder.dart';
import 'package:webtui_chat/features/ide_mobile/application/ide_talk_service.dart';
import 'package:webtui_chat/features/ide_mobile/presentation/screens/talk/ide_profile_screen.dart';
import 'package:webtui_chat/features/ide_mobile/presentation/screens/talk/ide_profile_usage.dart';
import 'package:webtui_chat/features/ide_mobile/presentation/widgets/markdown/ide_chart_view.dart';

import '../support/more_env.dart';
import '../support/rpc_env.dart';

Object? profileHandler(String op, Map<String, Object?> a) => switch (op) {
  'profile.show' => {
    'user': 'lam',
    'full': 'Đức Lâm',
    'email': 'lam@x.vn',
    'admin': false,
    'has_avatar': false,
    'projects': [
      {'name': 'web', 'mode': 'x', 'role': 'owner'},
    ],
    'usage': {
      'days': a['days'] ?? 30,
      'totals': {'input': 1000, 'output': 500, 'cost_usd': 1.5, 'requests': 3},
      'by_model': [
        {'model': 'opus', 'input': 800, 'output': 300, 'cost_usd': 1.2},
        {'model': 'haiku', 'input': 200, 'output': 200, 'cost_usd': 0.3},
      ],
      'by_project': [],
    },
  },
  'profile.usage_daily' => {
    'items': [
      {'day': '2026-11-17', 'input': 10, 'output': 5, 'cost_usd': 0.1},
      {'day': '2026-11-18', 'input': 20, 'output': 9, 'cost_usd': 0.2},
    ],
  },
  'ai.usage' => {
    'claude': {'id': 'c1', 'label': 'Claude chung'},
    'codex': <String, Object?>{},
    'project': 'web',
    'granted': [],
  },
  'ai.routes' => const IdeFakeError('forbidden'),
  _ => const IdeFakeError('not_found'),
};

void main() {
  testWidgets('hồ sơ có profile.usage_daily: biểu đồ theo ngày', (t) async {
    final env = await pumpMore(
      t,
      const IdeProfileScreen(),
      profileHandler,
      ops: {'profile.show', 'profile.usage_daily', 'ai.usage', 'ai.routes'},
    );
    await settle(t);
    expect(find.text('Đức Lâm'), findsOneWidget);
    expect(env.calls, contains('profile.usage_daily'));
    expect(find.byType(IdeChartView), findsOneWidget);
    // ai.routes bị cấm: báo không có quyền, trang vẫn dùng được.
    t.view.physicalSize = const Size(411, 5000);
    await t.pump();
    await settle(t);
    expect(env.calls, contains('ai.routes'));
    expect(find.textContaining('không có quyền'), findsOneWidget);
  });

  testWidgets('hồ sơ không có usage_daily và ai.routes: vẽ theo model', (
    t,
  ) async {
    final env = await pumpMore(
      t,
      const IdeProfileScreen(),
      profileHandler,
      ops: {'profile.show'},
    );
    await settle(t);
    expect(env.calls, isNot(contains('profile.usage_daily')));
    expect(env.calls, isNot(contains('ai.routes')));
    expect(env.calls, isNot(contains('ai.usage')));
    expect(find.byType(IdeChartView), findsOneWidget);
    expect(find.text('Đức Lâm'), findsOneWidget);
  });

  test('biểu đồ: không có dữ liệu thì null; số xấu không làm hỏng', () {
    expect(ideProfileChartSpec(daily: null, byModel: const []), isNull);
  });

  test('talk.share là ★: đi qua need_step; stop:true thì không', () async {
    final seen = <String>[];
    final env = IdeRpcEnv(
      (op, a) => ideFakeSilent,
      ops: ['talk.share'],
      step: (r) async {
        seen.add(r.op);
        return 'chu-ky';
      },
    );
    await env.up();
    final svc = IdeTalkService(env.rpc);
    final call = svc.share('a' * 32);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    final req = env.lastSocket!.sentOfType('op').single['req'];
    env.lastSocket!.emit({
      'type': 'need_step',
      'req': req,
      'challenge': 'Y2g=',
      'summary': 'Chia sẻ',
    });
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(seen, ['talk.share']);
    env.lastSocket!.emit({
      'type': 'result',
      'req': req,
      'ok': true,
      'data': {'link': 'x/y', 'url': 'https://x/y'},
    });
    final r = await call;
    expect(r.url, 'https://x/y');
    await env.dispose();
  });

  test('stopShare gửi stop:true', () async {
    final env = IdeRpcEnv((op, a) => <String, Object?>{}, ops: ['talk.share']);
    await env.up();
    await IdeTalkService(env.rpc).stopShare('a' * 32);
    final f = env.lastSocket!.sentOfType('op').single;
    expect((f['args']! as Map)['stop'], true);
    await env.dispose();
  });

  test('bộ mã ảnh đại diện ra đúng PNG 256x256, ≤ 300 KB', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await TestAsyncUtils.guard<void>(() async {});
    final out = await _encodeSample();
    expect(out.length, lessThanOrEqualTo(300 * 1024));
    expect(out.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
    final bd = ByteData.sublistView(out);
    expect(bd.getUint32(16), 256);
    expect(bd.getUint32(20), 256);
  });

  test('ảnh hỏng thì báo không đọc được', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await expectLater(
      const DartUiAvatarEncoder().encode(Uint8List.fromList([1, 2, 3])),
      throwsA(isA<IdeAvatarUnreadable>()),
    );
  });
}

Future<Uint8List> _encodeSample() async {
  // Ảnh nguồn chữ nhật 600x400 dựng bằng dart:ui.
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  c.drawRect(
    const Rect.fromLTWH(0, 0, 600, 400),
    Paint()
      ..shader = ui.Gradient.linear(Offset.zero, const Offset(600, 400), [
        Colors.red,
        Colors.blue,
      ]),
  );
  final img = await rec.endRecording().toImage(600, 400);
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  return const DartUiAvatarEncoder().encode(data!.buffer.asUint8List());
}

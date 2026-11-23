import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/ide_mobile/domain/ide_monitor_models.dart';
import 'package:webtui_chat/features/ide_mobile/presentation/screens/tools/ide_monitor_screen.dart';

import 'tools_env.dart';

const _ops = {
  'monitor.list',
  'monitor.info',
  'monitor.live',
  'monitor.history',
};

Map<String, Object?> _list() => {
  'items': [
    {
      'key': 'sys:web1',
      'name': 'web1',
      'label': 'Máy web',
      'state': {
        'ok': true,
        'summary': {
          'cpu': 12,
          'mem': 40,
          'alert_list': [
            {
              'level': 'bad',
              'code': 'disk',
              'args': ['/', 93],
            },
          ],
        },
      },
    },
  ],
};

Map<String, Object?> _live([num cpu = 35]) => {
  'cpu': {'total': cpu},
  'mem': {'total': 1000000000, 'used': 400000000},
  'load': {'l1': 0.5},
  'net': {'rx': 1000, 'tx': 500},
  'disk': {'read': 0, 'write': 10},
  'procs': 120,
};

Map<String, Object?> _history({bool weird = false}) => {
  'points': [
    for (var i = 0; i < 6; i++)
      {
        't': 1700000000 + i * 60,
        'cpu': weird ? (i.isEven ? -50 : 1e300) : 10.0 + i,
        'mem': weird ? 1e300 : 400000000,
        'mt': weird ? 0 : 1000000000,
        'l1': weird ? -3 : 0.4,
      },
  ],
};

IdeFakeHandler _handler({
  Object? list,
  Object? live,
  Object? info,
  Object? history,
}) =>
    (op, a) => switch (op) {
      'monitor.list' => list ?? _list(),
      'monitor.live' => live ?? _live(),
      'monitor.info' => info ?? {'os': 'Ubuntu 24.04', 'ncpu': 2, 'disks': []},
      'monitor.history' => history ?? _history(),
      _ => {},
    };

void main() {
  testWidgets('tải được số liệu, cảnh báo đã dịch', (t) async {
    await pumpTool(
      t,
      const IdeMonitorScreen(project: 'web'),
      _handler(),
      ops: _ops,
    );
    expect(find.byKey(const Key('ide_monitor_view')), findsOneWidget);
    expect(find.byKey(const Key('ide_monitor_alert_disk')), findsOneWidget);
    expect(find.textContaining('93'), findsWidgets);
    expect(find.byKey(const Key('ide_monitor_chart')), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('rỗng', (t) async {
    await pumpTool(
      t,
      const IdeMonitorScreen(project: 'web'),
      _handler(list: {'items': []}),
      ops: _ops,
    );
    expect(find.byKey(const Key('ide_monitor_view')), findsNothing);
    expect(find.text('Chưa có máy chủ để giám sát'), findsOneWidget);
  });

  testWidgets('lỗi tải danh sách có nút thử lại', (t) async {
    await pumpTool(
      t,
      const IdeMonitorScreen(project: 'web'),
      (op, a) => const IdeFakeError('internal'),
      ops: _ops,
    );
    expect(find.text('Thử lại'), findsOneWidget);
  });

  testWidgets('op monitor.list không có thì báo không hỗ trợ', (t) async {
    await pumpTool(
      t,
      const IdeMonitorScreen(project: 'web'),
      _handler(),
      ops: {'x.y'},
    );
    expect(find.byKey(const Key('ide_monitor_view')), findsNothing);
  });

  testWidgets('không có monitor.history thì ẩn biểu đồ, không gọi', (t) async {
    final env = await pumpTool(
      t,
      const IdeMonitorScreen(project: 'web'),
      _handler(),
      ops: _ops.difference({'monitor.history'}),
    );
    expect(sentOps(env, 'monitor.history'), isEmpty);
    expect(find.byKey(const Key('ide_monitor_chart')), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('số cực đoan / âm không làm vỡ biểu đồ', (t) async {
    await pumpTool(
      t,
      const IdeMonitorScreen(project: 'web'),
      _handler(history: _history(weird: true), live: _live(1e300)),
      ops: _ops,
    );
    expect(t.takeException(), isNull);
    for (final m in [0, 1, 2, 3]) {
      await t.tap(find.byKey(Key('ide_monitor_metric_$m')));
      await t.pump();
    }
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('hỏi live định kỳ, rời màn thì dừng', (t) async {
    final env = await pumpTool(
      t,
      const IdeMonitorScreen(project: 'web'),
      _handler(),
      ops: _ops,
    );
    final first = sentOps(env, 'monitor.live').length;
    expect(first, 1);
    await t.pump(const Duration(seconds: 5));
    await settle(t);
    expect(sentOps(env, 'monitor.live').length, greaterThan(first));
    await t.pumpWidget(const SizedBox());
    final after = sentOps(env, 'monitor.live').length;
    await t.pump(const Duration(seconds: 30));
    expect(sentOps(env, 'monitor.live').length, after);
  });

  testWidgets('forbidden dừng hẳn việc hỏi tự động', (t) async {
    final env = await pumpTool(
      t,
      const IdeMonitorScreen(project: 'web'),
      _handler(live: const IdeFakeError('forbidden')),
      ops: _ops,
    );
    expect(sentOps(env, 'monitor.live'), hasLength(1));
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(seconds: 6));
      await settle(t);
    }
    expect(sentOps(env, 'monitor.live'), hasLength(1));
    expect(find.byKey(const Key('ide_monitor_live_error')), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  test('IdeMonHistory.parse: NaN / vô cực thành null, không làm vỡ', () {
    final h = IdeMonHistory.parse({
      'points': [
        {'t': 1700000000, 'cpu': double.nan, 'mem': double.infinity, 'mt': 0},
        {'t': 1e30, 'cpu': -1, 'l1': double.negativeInfinity},
      ],
    });
    for (final p in h.points) {
      for (final v in [p.cpu, p.mem, p.load, p.rx, p.tx]) {
        expect(v == null || (v.isFinite && v >= 0), isTrue);
      }
    }
  });
}

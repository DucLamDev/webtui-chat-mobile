import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/ide_mobile/presentation/screens/tools/ide_agents_screen.dart';
import 'package:webtui_chat/features/ide_mobile/presentation/screens/tools/ide_skills_screen.dart';

import 'tools_env.dart';

const _skillOps = {
  'skills.list',
  'skills.ensure',
  'skills.install',
  'skills.update',
  'skills.remove',
};

Map<String, Object?> _skills({bool writable = true}) => {
  'project': 'web',
  'writable': writable,
  'installed': [
    {
      'name': 'viet-test',
      'description': 'Viết test',
      'version': '1.0',
      'library_version': '1.1',
      'installed_version': '1.0',
      'state': 'outdated',
      'source': 'library',
    },
  ],
  'library': [
    {'name': 'ra-soat', 'description': 'Rà soát mã', 'version': '2.0'},
  ],
};

void main() {
  group('Skill', () {
    testWidgets('tải được danh sách, có nút cài / cập nhật / gỡ', (t) async {
      await pumpTool(
        t,
        const IdeSkillsScreen(project: 'web'),
        (op, _) => op == 'skills.list' ? _skills() : {},
        ops: _skillOps,
      );
      expect(find.text('viet-test'), findsWidgets);
      expect(
        find.byKey(const Key('ide_tool_update_viet-test')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('ide_tool_remove_viet-test')),
        findsOneWidget,
      );
    });

    testWidgets('không ghi được thì ẩn mọi nút', (t) async {
      await pumpTool(
        t,
        const IdeSkillsScreen(project: 'web'),
        (op, _) => op == 'skills.list' ? _skills(writable: false) : {},
        ops: _skillOps,
      );
      expect(find.byKey(const Key('ide_tool_update_viet-test')), findsNothing);
      expect(find.byKey(const Key('ide_tool_remove_viet-test')), findsNothing);
    });

    testWidgets('op remove không có trong ready.ops thì ẩn nút gỡ', (t) async {
      await pumpTool(
        t,
        const IdeSkillsScreen(project: 'web'),
        (op, _) => op == 'skills.list' ? _skills() : {},
        ops: _skillOps.difference({'skills.remove'}),
      );
      expect(find.byKey(const Key('ide_tool_remove_viet-test')), findsNothing);
      expect(
        find.byKey(const Key('ide_tool_update_viet-test')),
        findsOneWidget,
      );
    });

    testWidgets('rỗng', (t) async {
      await pumpTool(
        t,
        const IdeSkillsScreen(project: 'web'),
        (op, _) => op == 'skills.list' ? {'installed': [], 'library': []} : {},
        ops: _skillOps,
      );
      expect(find.byKey(const Key('ide_tool_update_viet-test')), findsNothing);
      expect(find.byType(ListView), findsWidgets);
    });

    testWidgets('lỗi có nút thử lại, bấm thì tải lại', (t) async {
      var fail = true;
      final env = await pumpTool(t, const IdeSkillsScreen(project: 'web'), (
        op,
        _,
      ) {
        if (op == 'skills.list') {
          return fail ? const IdeFakeError('internal') : _skills();
        }
        return {};
      }, ops: _skillOps);
      expect(find.text('Thử lại'), findsOneWidget);
      fail = false;
      await t.tap(find.text('Thử lại'));
      await settle(t);
      expect(find.text('viet-test'), findsWidgets);
      expect(sentOps(env, 'skills.list'), hasLength(2));
    });

    testWidgets('không quyền (forbidden)', (t) async {
      await pumpTool(
        t,
        const IdeSkillsScreen(project: 'web'),
        (op, _) => op == 'skills.list' ? const IdeFakeError('forbidden') : {},
        ops: _skillOps,
      );
      expect(find.byKey(const Key('ide_tool_update_viet-test')), findsNothing);
      expect(find.text('Thử lại'), findsNothing);
    });

    testWidgets('gỡ là ★: hỏi lại rồi đi qua need_step', (t) async {
      var steps = 0;
      final env = await pumpTool(
        t,
        const IdeSkillsScreen(project: 'web'),
        (op, _) => op == 'skills.remove'
            ? ideFakeSilent
            : (op == 'skills.list' ? _skills() : {}),
        ops: _skillOps,
        step: (r) async {
          steps++;
          expect(r.op, 'skills.remove');
          return 'chu-ky';
        },
      );
      await t.tap(find.byKey(const Key('ide_tool_remove_viet-test')));
      await settle(t);
      expect(sentOps(env, 'skills.remove'), isEmpty);
      await t.tap(find.text('Gỡ').last);
      await settle(t);
      expect(sentOps(env, 'skills.remove'), hasLength(1));
      await emitNeedStep(t, env);
      expect(steps, 1);
      expect(env.lastSocket!.sentOfType('step').single['sig'], 'chu-ky');
      final req = env.lastSocket!.sentOfType('op').last['req'];
      env.lastSocket!.emit({
        'type': 'result',
        'req': req,
        'ok': true,
        'data': {},
      });
      await settle(t);
    });

    testWidgets('cài không bấm đôi được', (t) async {
      final env = await pumpTool(
        t,
        const IdeSkillsScreen(project: 'web'),
        (op, _) => op == 'skills.install'
            ? ideFakeSilent
            : (op == 'skills.list' ? _skills() : {}),
        ops: _skillOps,
      );
      final btn = find.byKey(const Key('ide_tool_install_ra-soat'));
      await t.ensureVisible(btn);
      await t.tap(btn);
      await t.pump();
      await t.tap(btn, warnIfMissed: false);
      await settle(t);
      expect(sentOps(env, 'skills.install'), hasLength(1));
      final req = env.lastSocket!.sentOfType('op').last['req'];
      env.lastSocket!.emit({
        'type': 'result',
        'req': req,
        'ok': true,
        'data': {},
      });
      await settle(t);
    });

    testWidgets('chữ hệ thống cỡ 1,6 không tràn', (t) async {
      await pumpTool(
        t,
        const IdeSkillsScreen(project: 'web'),
        (op, _) => op == 'skills.list' ? _skills() : {},
        ops: _skillOps,
        textScale: 1.6,
      );
      expect(t.takeException(), isNull);
    });
  });

  group('AI Agent', () {
    const ops = {'agents.session', 'agents.status'};
    Map<String, Object?> session() => {
      'days': 7,
      'totals': {'agents': 2, 'runs': 5, 'today': 1, 'running': 0},
      'agents': [
        {
          'kind': 'agent',
          'name': 'rà-soát',
          'description': 'Rà soát mã',
          'use': {'runs': 3},
        },
      ],
      'commands': <Object?>[],
      'recent': [
        {'agent': 'rà-soát', 'desc': 'x', 'status': 'ok', 'ms': -5},
      ],
    };

    testWidgets('tải được, số âm / vô cực không làm vỡ', (t) async {
      await pumpTool(
        t,
        const IdeAgentsScreen(project: 'web'),
        (op, _) => op == 'agents.session' ? session() : {'items': []},
        ops: ops,
      );
      expect(find.byKey(const Key('ide_agents_list')), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('lỗi có nút thử lại', (t) async {
      await pumpTool(
        t,
        const IdeAgentsScreen(project: 'web'),
        (op, _) => const IdeFakeError('internal'),
        ops: ops,
      );
      expect(find.text('Thử lại'), findsOneWidget);
    });

    testWidgets('không có op nào thì báo không hỗ trợ', (t) async {
      await pumpTool(
        t,
        const IdeAgentsScreen(project: 'web'),
        (op, _) => {},
        ops: {'x.y'},
      );
      expect(find.byKey(const Key('ide_agents_list')), findsNothing);
    });
  });
}

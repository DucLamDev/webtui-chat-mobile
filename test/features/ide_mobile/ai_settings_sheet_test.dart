import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/app/providers/foundation_providers.dart';
import 'package:webtui_chat/design_system/theme/webtui_theme.dart';
import 'package:webtui_chat/design_system/tokens/webtui_colors.dart';
import 'package:webtui_chat/features/ide_mobile/application/ide_ai_session_controller.dart';
import 'package:webtui_chat/features/ide_mobile/presentation/controllers/ide_ai_controllers.dart';
import 'package:webtui_chat/features/ide_mobile/presentation/widgets/ai/ide_session_settings_sheet.dart';

import 'ai_session_controller_test.dart' show Rig, stateFrame;

void main() {
  Future<Rig> open(
    WidgetTester tester, {
    Map<String, Object?>? extra,
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.physicalSize = const Size(900, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final rig = Rig();
    WebTuiColors.apply(brightness);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ideConnectionProvider.overrideWithValue(rig.connection),
          ideAiSessionControllerProvider.overrideWith(
            (ref, target) => rig.controller..start(),
          ),
        ],
        child: MaterialApp(
          theme: brightness == Brightness.dark
              ? WebTuiTheme.dark()
              : WebTuiTheme.light(),
          home: const Scaffold(
            body: IdeSessionSettingsSheet(
              target: IdeAiOpenTarget.existing('k1'),
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(() => rig.settle());
    rig.socket.emit(stateFrame(extra: extra));
    await tester.runAsync(() => rig.settle());
    await tester.pump(const Duration(milliseconds: 20));
    return rig;
  }

  Future<void> close(WidgetTester tester, Rig rig) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => rig.connection.dispose());
    WebTuiColors.apply(Brightness.light);
  }

  final base = <String, Object?>{
    'settings': {
      'model': 'opus',
      'effort': 'high',
      'fast': false,
      'autoSaveImages': false,
      'permissions': {
        'mode': 'ask',
        'tools': <Object?>[],
        'commands': <Object?>[],
      },
    },
    'models': [
      {
        'id': 'opus',
        'name': 'Opus',
        'efforts': ['low', 'high'],
      },
    ],
  };

  testWidgets('mức nghĩ chỉ gồm mức model hỗ trợ; đổi gửi configure', (
    tester,
  ) async {
    final rig = await open(tester, extra: base);
    expect(find.byKey(const Key('ide_set_effort_xhigh')), findsNothing);
    await tester.tap(find.byKey(const Key('ide_set_effort_low')));
    await tester.pump();
    final frame = rig.socket.sentOfType('configure').single;
    expect(frame['settings'], {'effort': 'low'});
    expect(frame.containsKey('action'), false);
    await close(tester, rig);
  });

  testWidgets('chế độ nhanh chỉ hiện khi fastAllowed', (tester) async {
    var rig = await open(tester, extra: base);
    expect(find.byKey(const Key('ide_set_fast')), findsNothing);
    await close(tester, rig);
    rig = await open(tester, extra: {...base, 'fastAllowed': true});
    expect(find.byKey(const Key('ide_set_fast')), findsOneWidget);
    await tester.tap(find.byKey(const Key('ide_set_fast')));
    await tester.pump();
    expect(rig.socket.sentOfType('configure').single['settings'], {
      'fast': true,
    });
    await close(tester, rig);
  });

  testWidgets('Lập kế hoạch và Đội AI gửi permissions đúng', (tester) async {
    final rig = await open(tester, extra: base);
    await tester.tap(find.byKey(const Key('ide_set_mode_plan')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('ide_set_mode_team')));
    await tester.pump();
    final frames = rig.socket.sentOfType('configure').toList();
    expect((frames[0]['settings']! as Map)['permissions'], {
      'mode': 'plan',
      'tools': <Object?>[],
      'commands': <Object?>[],
    });
    expect((frames[1]['settings']! as Map)['permissions'], {
      'mode': 'plan',
      'tools': <Object?>[],
      'commands': <Object?>[],
      'team': true,
    });
    await close(tester, rig);
  });

  testWidgets('"Cho phép hết" hỏi lại hai lần mới gửi', (tester) async {
    final rig = await open(tester, extra: base);
    await tester.tap(find.byKey(const Key('ide_set_mode_all')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tiếp tục'));
    await tester.pumpAndSettle();
    expect(rig.socket.sentOfType('configure'), isEmpty);
    await tester.tap(find.text('Bật'));
    await tester.pumpAndSettle();
    expect(
      ((rig.socket.sentOfType('configure').single['settings']!
              as Map)['permissions']
          as Map)['mode'],
      'all',
    );
    await close(tester, rig);
  });

  testWidgets('"Cho phép hết": huỷ ở lần hai thì không gửi', (tester) async {
    final rig = await open(tester, extra: base);
    await tester.tap(find.byKey(const Key('ide_set_mode_all')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tiếp tục'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Huỷ'));
    await tester.pumpAndSettle();
    expect(rig.socket.sentOfType('configure'), isEmpty);
    await close(tester, rig);
  });

  testWidgets('chat mới hỏi lại rồi gửi reset', (tester) async {
    final rig = await open(tester, extra: base);
    await tester.tap(find.byKey(const Key('ide_set_new')));
    await tester.pumpAndSettle();
    expect(rig.socket.sentOfType('reset'), isEmpty);
    await tester.tap(find.widgetWithText(FilledButton, 'Chat mới'));
    await tester.pumpAndSettle();
    expect(rig.socket.sentOfType('reset'), hasLength(1));
    await close(tester, rig);
  });

  testWidgets('thu gọn ngữ cảnh gửi compact và hiện % đã dùng', (tester) async {
    final rig = await open(
      tester,
      extra: {
        ...base,
        'context': {'percent': 42},
      },
    );
    expect(find.text('Đã dùng 42%'), findsOneWidget);
    await tester.tap(find.byKey(const Key('ide_set_compact')));
    await tester.pump();
    expect(rig.socket.sentOfType('compact'), hasLength(1));
    await close(tester, rig);
  });

  testWidgets('lịch sử: tải danh sách rồi load', (tester) async {
    final rig = await open(tester, extra: base);
    await tester.tap(find.byKey(const Key('ide_set_history')));
    await tester.pump();
    await tester.runAsync(() => rig.settle());
    expect(rig.socket.sentOfType('history'), hasLength(1));
    rig.socket.emit({
      'type': 'history',
      'entries': [
        {'id': 'h1', 'title': 'Làm trang đăng nhập', 'preview': 'xin chào'},
      ],
    });
    await tester.runAsync(() => rig.settle());
    await tester.pumpAndSettle();
    expect(find.text('Làm trang đăng nhập'), findsOneWidget);
    await tester.tap(find.byKey(const Key('ide_history_h1')));
    await tester.pumpAndSettle();
    expect(rig.socket.sentOfType('load').single['id'], 'h1');
    await close(tester, rig);
  });

  testWidgets('việc nền: dừng gửi stop_task', (tester) async {
    final rig = await open(
      tester,
      extra: {
        ...base,
        'tasks': [
          {'id': 't1', 'title': 'npm run dev', 'status': 'running'},
        ],
      },
    );
    await tester.tap(find.byKey(const Key('ide_set_tasks')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ide_task_stop_t1')));
    await tester.pump();
    expect(rig.socket.sentOfType('stop_task').single['task'], 't1');
    await close(tester, rig);
  });

  testWidgets('chỉ xem: nút đổi cài đặt bị khoá, nền tối vẫn dựng', (
    tester,
  ) async {
    final rig = await open(
      tester,
      extra: {...base, 'fastAllowed': true},
      brightness: Brightness.dark,
    );
    rig.socket.emit({'type': 'role', 'control': false, 'free': false});
    await tester.runAsync(() => rig.settle());
    await tester.pump(const Duration(milliseconds: 20));
    await tester.tap(find.byKey(const Key('ide_set_effort_low')));
    await tester.tap(find.byKey(const Key('ide_set_fast')));
    await tester.pump();
    expect(rig.socket.sentOfType('configure'), isEmpty);
    await close(tester, rig);
  });

  testWidgets('không có lựa chọn "Tự động" khi phiên chưa ở chế độ đó', (
    tester,
  ) async {
    final rig = await open(tester, extra: base);
    expect(find.byKey(const Key('ide_set_mode_auto')), findsNothing);
    expect(find.byKey(const Key('ide_set_mode_ask')), findsOneWidget);
    await close(tester, rig);
  });

  testWidgets('phiên đang "Tự động" (đặt từ máy tính): hiện, không chọn được', (
    tester,
  ) async {
    final rig = await open(
      tester,
      extra: {
        ...base,
        'settings': {
          ...base['settings']! as Map<String, Object?>,
          'permissions': {
            'mode': 'auto',
            'tools': <Object?>[],
            'commands': <Object?>[],
          },
        },
      },
    );
    final tile = find.byKey(const Key('ide_set_mode_auto'));
    expect(tile, findsOneWidget);
    expect(
      find.text('Đang bật từ máy tính. Điện thoại không bật được chế độ này.'),
      findsOneWidget,
    );
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(rig.socket.sentOfType('configure'), isEmpty);
    // Chọn chế độ khác vẫn được.
    await tester.tap(find.byKey(const Key('ide_set_mode_ask')));
    await tester.pump();
    expect(
      ((rig.socket.sentOfType('configure').single['settings']!
              as Map)['permissions']
          as Map)['mode'],
      'ask',
    );
    await close(tester, rig);
  });
}

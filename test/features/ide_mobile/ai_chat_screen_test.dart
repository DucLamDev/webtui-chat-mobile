import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/app/providers/foundation_providers.dart';
import 'package:webtui_chat/design_system/theme/webtui_theme.dart';
import 'package:webtui_chat/design_system/tokens/webtui_colors.dart';
import 'package:webtui_chat/features/ide_mobile/presentation/controllers/ide_ai_controllers.dart';
import 'package:webtui_chat/features/ide_mobile/presentation/screens/ide_ai_chat_screen.dart';

import 'ai_session_controller_test.dart' show Rig, stateFrame;

void main() {
  Future<Rig> open(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
    bool withState = true,
    Map<String, Object?>? extra,
    Map<String, Object?>? role,
  }) async {
    final rig = Rig();
    WebTuiColors.apply(brightness);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ideConnectionProvider.overrideWithValue(rig.connection),
          ideAiSessionControllerProvider.overrideWith((ref, target) {
            return rig.controller..start();
          }),
        ],
        child: MaterialApp(
          theme: brightness == Brightness.dark
              ? WebTuiTheme.dark()
              : WebTuiTheme.light(),
          home: IdeAiChatScreen(sessionKey: 'k1', autoOpenApprovals: false),
        ),
      ),
    );
    await tester.runAsync(() => rig.settle());
    if (withState) {
      rig.socket.emit(stateFrame(extra: extra));
      if (role != null) rig.socket.emit({'type': 'role', ...role});
      await tester.runAsync(() => rig.settle());
    }
    await tester.pump(const Duration(milliseconds: 20));
    return rig;
  }

  Future<void> close(WidgetTester tester, Rig rig) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      await rig.connection.dispose();
    });
    WebTuiColors.apply(Brightness.light);
  }

  final messages = <Object?>[
    {'id': 'u1', 'role': 'user', 'text': 'Sửa lỗi đăng nhập'},
    {'id': 'a1', 'role': 'assistant', 'text': 'Đã **sửa** xong.'},
  ];

  for (final mode in Brightness.values) {
    testWidgets('hiện tin người dùng và AI (${mode.name})', (tester) async {
      final rig = await open(
        tester,
        brightness: mode,
        extra: {'messages': messages},
      );
      expect(find.text('Sửa lỗi đăng nhập'), findsOneWidget);
      expect(find.byKey(const Key('ide_ai_input')), findsOneWidget);
      await close(tester, rig);
    });
  }

  testWidgets('chưa có state thì hiện đang mở phiên', (tester) async {
    final rig = await open(tester, withState: false);
    expect(find.text('Đang mở phiên…'), findsOneWidget);
    await close(tester, rig);
  });

  testWidgets('phiên rỗng hiện trạng thái rỗng', (tester) async {
    final rig = await open(tester);
    expect(find.text('Chưa có tin nhắn'), findsOneWidget);
    await close(tester, rig);
  });

  testWidgets('gõ "/" mở menu lệnh, chọn chèn vào ô', (tester) async {
    final rig = await open(
      tester,
      extra: {
        'messages': messages,
        'commands': [
          {'name': 'review', 'description': 'Rà soát'},
        ],
      },
    );
    await tester.enterText(find.byKey(const Key('ide_ai_input')), '/');
    await tester.pump();
    expect(find.byKey(const Key('ide_slash_menu')), findsOneWidget);
    expect(find.byKey(const Key('ide_slash_/status')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('ide_ai_input')), '/rev');
    await tester.pump();
    expect(find.byKey(const Key('ide_slash_/review')), findsOneWidget);
    expect(find.byKey(const Key('ide_slash_/status')), findsNothing);
    await tester.tap(find.byKey(const Key('ide_slash_/review')));
    await tester.pump();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('ide_ai_input')))
          .controller!
          .text,
      '/review ',
    );
    await close(tester, rig);
  });

  testWidgets('gõ "@" gợi ý tệp đã sửa và chèn đường dẫn', (tester) async {
    final rig = await open(
      tester,
      extra: {
        'messages': messages,
        'changes': [
          {'path': '/srv/app/lib/main.dart', 'added': 1, 'removed': 0},
        ],
      },
    );
    await tester.enterText(find.byKey(const Key('ide_ai_input')), 'xem @mai');
    await tester.pump();
    expect(find.byKey(const Key('ide_mention_menu')), findsOneWidget);
    await tester.tap(
      find.byKey(const Key('ide_mention_/srv/app/lib/main.dart')),
    );
    await tester.pump();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('ide_ai_input')))
          .controller!
          .text,
      'xem @/srv/app/lib/main.dart ',
    );
    await close(tester, rig);
  });

  testWidgets('gửi tin gửi khung send có type, không có action', (
    tester,
  ) async {
    final rig = await open(tester, extra: {'messages': messages});
    await tester.enterText(find.byKey(const Key('ide_ai_input')), 'Chạy test');
    await tester.pump();
    await tester.tap(find.byKey(const Key('ide_ai_send')));
    await tester.pump();
    final send = rig.socket.sentOfType('send').single;
    expect(send['text'], 'Chạy test');
    expect(send['id'], startsWith('m-'));
    expect(send.containsKey('action'), false);
    await close(tester, rig);
  });

  testWidgets('đang chạy: nút Dừng gửi interrupt', (tester) async {
    final rig = await open(tester, extra: {'messages': messages, 'busy': true});
    expect(find.byKey(const Key('ide_ai_stop')), findsOneWidget);
    await tester.tap(find.byKey(const Key('ide_ai_stop')));
    await tester.pump();
    expect(rig.socket.sentOfType('interrupt'), hasLength(1));
    await close(tester, rig);
  });

  testWidgets(
    'chỉ xem: dải thông báo, ô gõ khoá, Điều khiển từ đây gửi claim',
    (tester) async {
      final rig = await open(
        tester,
        extra: {'messages': messages},
        role: {'control': false, 'free': false},
      );
      expect(find.byKey(const Key('ide_ai_view_only')), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byKey(const Key('ide_ai_input'))).enabled,
        false,
      );
      await tester.tap(find.text('Điều khiển từ đây'));
      await tester.pump();
      final claim = rig.socket.sentOfType('claim').single;
      expect(claim['take'], true);
      await close(tester, rig);
    },
  );

  testWidgets('có thẻ duyệt: nút Cần duyệt hiện số lượng', (tester) async {
    final rig = await open(
      tester,
      extra: {
        'messages': messages,
        'approvals': [
          {
            'id': 'a9',
            'method': 'claude/permission',
            'params': {
              'tool_name': 'Bash',
              'input': {'command': 'ls'},
            },
          },
        ],
      },
    );
    expect(find.text('Cần duyệt (1)'), findsOneWidget);
    await close(tester, rig);
  });

  testWidgets('đóng màn chat thì trả lại presenter vân tay trước đó', (
    tester,
  ) async {
    Future<bool> before(summary) async => true;
    final rig = Rig();
    final shown = ValueNotifier(true);
    late ProviderContainer container;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ideConnectionProvider.overrideWithValue(rig.connection),
          ideStepPresenterProvider.overrideWith((ref) => before),
          ideAiSessionControllerProvider.overrideWith(
            (ref, target) => rig.controller..start(),
          ),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            container = ProviderScope.containerOf(context);
            return ValueListenableBuilder<bool>(
              valueListenable: shown,
              builder: (_, on, _) => on
                  ? MaterialApp(
                      theme: WebTuiTheme.light(),
                      home: IdeAiChatScreen(
                        sessionKey: 'k1',
                        autoOpenApprovals: false,
                      ),
                    )
                  : const SizedBox(),
            );
          },
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    expect(container.read(ideStepPresenterProvider), isNot(same(before)));
    shown.value = false;
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    expect(container.read(ideStepPresenterProvider), same(before));
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => rig.connection.dispose());
  });

  testWidgets('phiên mới không có thư mục: báo lỗi, không mở phiên', (
    tester,
  ) async {
    final rig = Rig();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ideConnectionProvider.overrideWithValue(rig.connection),
          ideAiSessionControllerProvider.overrideWith(
            (ref, target) => throw StateError('không được mở phiên'),
          ),
        ],
        child: MaterialApp(
          theme: WebTuiTheme.light(),
          home: IdeAiChatScreen.newSession(kind: 'claude', root: '  '),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const Key('ide_ai_no_root')), findsOneWidget);
    expect(find.byKey(const Key('ide_ai_no_root_back')), findsOneWidget);
    expect(find.byKey(const Key('ide_ai_input')), findsNothing);
    expect(rig.aiSockets, isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => rig.connection.dispose());
  });

  testWidgets('gửi biểu mẫu khi mất kết nối: không hiện Đã gửi, báo lỗi', (
    tester,
  ) async {
    const form =
        '{"title":"Khảo sát","fields":[{"id":"ten","label":"Tên",'
        '"type":"text","required":true}],"submit":"Gửi đi"}';
    final rig = await open(
      tester,
      extra: {
        'messages': [
          {'id': 'a9', 'role': 'assistant', 'text': '```form\n$form\n```'},
        ],
      },
    );
    await tester.runAsync(() => rig.socket.drop());
    await tester.pump(const Duration(milliseconds: 5));
    await tester.enterText(find.byType(TextFormField).first, 'Lâm');
    await tester.tap(find.text('Gửi đi'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Đã gửi'), findsNothing);
    expect(rig.socket.sentOfType('send'), isEmpty);
    await close(tester, rig);
  });
}

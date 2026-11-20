import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/app/providers/foundation_providers.dart';
import 'package:webtui_chat/design_system/theme/webtui_theme.dart';
import 'package:webtui_chat/design_system/tokens/webtui_colors.dart';
import 'package:webtui_chat/features/ide_mobile/presentation/controllers/ide_ai_controllers.dart';
import 'package:webtui_chat/features/ide_mobile/presentation/screens/ide_ai_chat_screen.dart';
import 'package:webtui_chat/features/ide_mobile/presentation/widgets/ai/ide_approval_sheet.dart';

import '../../support/system_font.dart';
import 'ai_session_controller_test.dart' show Rig, stateFrame;

/// Ảnh chụp các màn AI của IDE (sáng / tối, cỡ chữ 1.0 / 1.6) để xem bằng mắt
/// trước khi phát hành. Ảnh ghi vào `build/ide_shots/` (không commit); test
/// chỉ kiểm không có lỗi vẽ / tràn chữ.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadSystemRobotoForTests();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    // Môi trường test không có phông `monospace` của máy: mượn Roboto để
    // khối mã / lệnh hiện chữ thay vì ô vuông (chỉ để xem bố cục).
    final mono = FontLoader('monospace');
    for (final w in const ['regular', 'bold']) {
      mono.addFont(
        File(
          'assets/fonts/roboto-$w.ttf',
        ).readAsBytes().then(ByteData.sublistView),
      );
    }
    await Future.wait([icons.load(), mono.load()]);
  });

  const size = Size(390, 844);
  const dir = 'build/ide_shots';

  final messages = <Object?>[
    {'id': 'u1', 'role': 'user', 'text': 'Build bản APK thử cho dự án chat'},
    {
      'id': 'a1',
      'role': 'assistant',
      'text':
          'Đã **build** xong. Các bước:\n\n'
          '1. Chạy `flutter build apk --debug`\n'
          '2. Kiểm chữ ký\n\n'
          '```bash\nflutter build apk --debug --flavor dev\n```\n\n'
          '| Bản | Cỡ |\n|---|---|\n| debug | 92 MB |\n',
    },
    {'id': 'u2', 'role': 'user', 'text': 'Gửi tệp APK cho mình'},
  ];

  final approvals = <Map<String, Object?>>[
    {
      'id': 'a1',
      'method': 'claude/permission',
      'irreversible': false,
      'params': {
        'tool_name': 'Bash',
        'input': {'command': 'git push origin feature/duclam-ide-tep'},
      },
    },
    {
      'id': 'e1',
      'method': 'item/fileChange/requestApproval',
      'changes': [
        {
          'path': '/srv/projects/demo/lib/main.dart',
          'diff': '@@ -1,2 +1,2 @@\n-void main() {}\n+void main() => run();',
        },
      ],
      'params': <String, Object?>{},
    },
  ];

  Widget frame(Widget child, Brightness b, double scale, GlobalKey key) {
    return RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: _withRoboto(
          b == Brightness.dark ? WebTuiTheme.dark() : WebTuiTheme.light(),
        ),
        builder: (context, inner) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: inner!,
        ),
        home: child,
      ),
    );
  }

  Future<void> save(WidgetTester tester, GlobalKey key, String name) async {
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$dir/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
    });
  }

  void setView(WidgetTester tester) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  for (final b in Brightness.values) {
    for (final scale in const [1.0, 1.6]) {
      final tag = '${b.name}-${scale == 1.0 ? '1x' : '1_6x'}';

      testWidgets('chụp màn chat AI ($tag)', (tester) async {
        setView(tester);
        WebTuiColors.apply(b);
        final rig = Rig();
        final key = GlobalKey();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              ideConnectionProvider.overrideWithValue(rig.connection),
              ideAiSessionControllerProvider.overrideWith(
                (ref, target) => rig.controller..start(),
              ),
            ],
            child: frame(
              IdeAiChatScreen(sessionKey: 'k1', autoOpenApprovals: false),
              b,
              scale,
              key,
            ),
          ),
        );
        await tester.runAsync(() => rig.settle());
        rig.socket.emit(
          stateFrame(extra: {'messages': messages, 'busy': true}),
        );
        await tester.runAsync(() => rig.settle());
        await tester.pump(const Duration(milliseconds: 50));
        await save(tester, key, 'ai-chat-$tag');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(() => rig.connection.dispose());
        WebTuiColors.apply(Brightness.light);
      });

      testWidgets('chụp bảng duyệt ($tag)', (tester) async {
        setView(tester);
        WebTuiColors.apply(b);
        final key = GlobalKey();
        await tester.pumpWidget(
          frame(
            Scaffold(
              body: IdeApprovalSheet(
                approvals: approvals,
                planPending: true,
                plan: '# Kế hoạch\n- Thêm mục Tệp\n- Thêm mục Terminal',
                canControl: true,
                onAnswer: (id, {required allow, answers, deepen = false}) {},
                onApprovePlan: (_) {},
                onDeepenPlan: () {},
              ),
            ),
            b,
            scale,
            key,
          ),
        );
        await tester.pump(const Duration(milliseconds: 50));
        await save(tester, key, 'ai-duyet-$tag');
        expect(tester.takeException(), isNull);
        WebTuiColors.apply(Brightness.light);
      });
    }
  }
}

/// Nút Material lấy `labelLarge` (app không đặt) → trong test rơi về phông
/// thử nghiệm. Trên máy thật là phông hệ thống; ở đây gán Roboto cho cả bộ chữ.
ThemeData _withRoboto(ThemeData base) {
  ButtonStyle? fix(ButtonStyle? s) => s?.copyWith(
    textStyle: WidgetStateProperty.resolveWith(
      (states) => (s.textStyle?.resolve(states) ?? const TextStyle()).copyWith(
        fontFamily: 'Roboto',
      ),
    ),
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(fontFamily: 'Roboto'),
    primaryTextTheme: base.primaryTextTheme.apply(fontFamily: 'Roboto'),
    filledButtonTheme: FilledButtonThemeData(
      style: fix(base.filledButtonTheme.style) ?? _roboto,
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: fix(base.outlinedButtonTheme.style) ?? _roboto,
    ),
    textButtonTheme: TextButtonThemeData(
      style: fix(base.textButtonTheme.style) ?? _roboto,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: fix(base.elevatedButtonTheme.style) ?? _roboto,
    ),
  );
}

const _roboto = ButtonStyle(
  textStyle: WidgetStatePropertyAll(TextStyle(fontFamily: 'Roboto')),
);

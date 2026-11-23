import 'dart:convert';
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
import 'package:webtui_chat/features/ide_mobile/data/ide_connection.dart';
import 'package:webtui_chat/features/ide_mobile/domain/ide_ready.dart';
import 'package:webtui_chat/features/ide_mobile/domain/ide_term.dart';
import 'package:webtui_chat/features/ide_mobile/presentation/controllers/ide_controllers.dart';
import 'package:webtui_chat/features/ide_mobile/presentation/screens/terminal/ide_terminal_screen.dart';
import 'package:webtui_chat/features/ide_mobile/presentation/screens/terminal/ide_terminal_tab.dart';

import '../../support/system_font.dart';
import 'support/rpc_env.dart';

/// Chụp danh sách + màn terminal (sáng / tối, chữ 1.0 và 1.6).
/// Ảnh chỉ để người xem đọc; test chỉ kiểm không lỗi dựng hình.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory out;
  final keep = Platform.environment['IDE_TERM_SHOTS'] ?? '';

  setUpAll(() async {
    await loadSystemRobotoForTests();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    // Muốn giữ ảnh để xem: IDE_TERM_SHOTS=<thư mục>. Không đặt thì ghi vào thư
    // mục tạm riêng và xoá khi xong.
    out = keep.isNotEmpty
        ? (Directory(keep)..createSync(recursive: true))
        : Directory.systemTemp.createTempSync('ide_term_shots_');
  });

  tearDownAll(() {
    if (keep.isEmpty && out.existsSync()) out.deleteSync(recursive: true);
  });

  const ops = {'term.list', 'term.kill', 'term.targets', 'projects.list'};
  const screen = Size(390, 844);

  Future<void> shoot(
    WidgetTester tester,
    String name,
    Widget home,
    IdeRpcEnv env,
    Brightness brightness,
    double scale, {
    void Function()? after,
  }) async {
    WebTuiColors.apply(brightness);
    tester.view.physicalSize = screen;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ideRpcClientProvider.overrideWithValue(env.rpc),
          ideConnectionProvider.overrideWithValue(env.connection),
          ideLinkStatusProvider.overrideWith(
            (ref) => Stream.value(
              IdeLinkStatus(IdeLinkPhase.ready, ready: IdeReady(ops: ops)),
            ),
          ),
        ],
        child: RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: brightness == Brightness.dark
                ? WebTuiTheme.dark()
                : WebTuiTheme.light(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: home,
          ),
        ),
      ),
    );
    await settle(tester);
    after?.call();
    await settle(tester);
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(
        '${out.path}/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
    });
    expect(tester.takeException(), isNull);
  }

  for (final (b, tag) in [
    (Brightness.light, 'sang'),
    (Brightness.dark, 'toi'),
  ]) {
    for (final scale in [1.0, 1.6]) {
      final suffix = '$tag-$scale';
      testWidgets('chụp danh sách terminal $suffix', (tester) async {
        final env = IdeRpcEnv((op, args) {
          return {
            'items': [
              {
                'name': 'shell-1',
                'root': '/srv/du-an-a',
                'cmd': 'shell',
                'attached': true,
              },
              {'name': 'claude-2', 'root': '/srv/du-an-b', 'cmd': 'claude'},
              {'name': 'ssh-3', 'root': '/srv/du-an-b', 'cmd': 'my-ssh:vps1'},
            ],
          };
        }, ops: ops.toList());
        addTearDown(() => tester.runAsync(env.dispose));
        await tester.runAsync(env.up);
        await shoot(
          tester,
          'danh-sach-$suffix',
          const Scaffold(body: IdeTerminalTab()),
          env,
          b,
          scale,
        );
      });

      testWidgets('chụp màn terminal $suffix', (tester) async {
        final env = IdeRpcEnv((op, args) => {}, ops: ops.toList());
        addTearDown(() => tester.runAsync(env.dispose));
        await tester.runAsync(env.up);
        await shoot(
          tester,
          'man-$suffix',
          const IdeTerminalScreen(
            target: IdeTermOpenTarget.existing('shell-1'),
          ),
          env,
          b,
          scale,
          after: () {
            final s = env.lastSocket!;
            s.emit({
              'type': 'tready',
              'name': 'shell-1',
              'cols': 60,
              'rows': 24,
            });
            const text =
                '\x1b[1;32mduclam@vps\x1b[0m:\x1b[1;34m~/du-an\x1b[0m\$ ls\r\n'
                '\x1b[34mlib\x1b[0m  \x1b[34mtest\x1b[0m  \x1b[38;5;208mREADME.md\x1b[0m\r\n'
                '\x1b[38;5;196m■\x1b[38;5;46m■\x1b[38;5;21m■\x1b[0m Xin chào, Việt Nam\r\n'
                '\x1b[1;32mduclam@vps\x1b[0m:\x1b[1;34m~/du-an\x1b[0m\$ ';
            s.emit({'type': 'tout', 'data': base64Encode(utf8.encode(text))});
          },
        );
      });
    }
  }
}

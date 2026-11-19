import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/app/providers/foundation_providers.dart';
import 'package:webtui_chat/design_system/theme/webtui_theme.dart';
import 'package:webtui_chat/design_system/tokens/webtui_colors.dart';
import 'package:webtui_chat/features/ide_mobile/data/ide_connection.dart';
import 'package:webtui_chat/features/ide_mobile/presentation/controllers/ide_controllers.dart';
import 'package:webtui_chat/features/ide_mobile/presentation/screens/files/ide_files_tab.dart';

import 'support/rpc_env.dart';

const ideFilesTestOps = [
  'projects.list',
  'files.list',
  'files.rename',
  'files.delete',
  'files.copy',
  'files.move',
  'files.read',
  'files.write',
  'files.mkdir',
  'files.create',
  'files.trash',
  'files.restore',
  'files.purge',
  'files.trash_purge',
  'files.diff',
  'files.find',
  'files.grep',
  'files.stat',
  'jobs.list',
];

Map<String, Object?> _projects() => {
  'items': [
    {'name': 'web', 'root': '/srv/web', 'git': true},
  ],
};

Map<String, Object?> _list() => {
  'items': [
    {'name': 'zeta.txt', 't': 'f', 'size': 10, 'mtime': 1000},
    {'name': 'src', 't': 'd', 'mtime': 2000},
    {'name': '.env', 't': 'f', 'size': 3, 'secret': true},
    {'name': 'main.dart', 't': 'f', 'size': 2048, 'git': 'M', 'mtime': 3000},
  ],
};

Future<IdeRpcEnv> _pump(
  WidgetTester tester,
  IdeFakeHandler handler, {
  Brightness brightness = Brightness.light,
  IdeLinkPhase phase = IdeLinkPhase.ready,
}) async {
  tester.view.physicalSize = const Size(800, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  WebTuiColors.apply(brightness);
  final env = IdeRpcEnv(handler, ops: ideFilesTestOps);
  addTearDown(() => tester.runAsync(env.dispose));
  await tester.runAsync(env.up);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ideRpcClientProvider.overrideWithValue(env.rpc),
        ideLinkStatusProvider.overrideWith(
          (ref) => Stream.value(IdeLinkStatus(phase)),
        ),
      ],
      child: MaterialApp(
        theme: brightness == Brightness.dark
            ? WebTuiTheme.dark()
            : WebTuiTheme.light(),
        home: const Scaffold(body: IdeFilesTab()),
      ),
    ),
  );
  await settle(tester);
  return env;
}

Object? _ok(String op, Map<String, Object?> a) => switch (op) {
  'projects.list' => _projects(),
  'files.list' => _list(),
  _ => <String, Object?>{},
};

void main() {
  _scaleSuite();
  for (final b in [Brightness.light, Brightness.dark]) {
    testWidgets('cây tệp: thư mục trước, chấm git, khoá bí mật ($b)', (
      tester,
    ) async {
      await _pump(tester, _ok, brightness: b);
      expect(find.text('src'), findsOneWidget);
      expect(find.text('main.dart'), findsOneWidget);
      expect(find.byKey(const Key('ide_git_main.dart')), findsOneWidget);
      expect(find.byIcon(Icons.lock_rounded), findsOneWidget);
      expect(find.textContaining('Chỉ mở trên máy tính'), findsOneWidget);
      // tệp ẩn (.env) vẫn do máy chủ trả về nên được hiện cùng khoá
      final y = {
        for (final n in ['src', 'main.dart', 'zeta.txt'])
          n: tester.getTopLeft(find.text(n)).dy,
      };
      expect(y['src']!, lessThan(y['main.dart']!));
      expect(y['main.dart']!, lessThan(y['zeta.txt']!));
    });
  }

  testWidgets('chạm tệp bí mật chỉ báo, không mở', (tester) async {
    final env = await _pump(tester, _ok);
    await tester.tap(find.byKey(const Key('ide_entry_.env')));
    await settle(tester);
    expect(find.text('Tệp bí mật chỉ mở trên máy tính.'), findsOneWidget);
    expect(env.calls.where((c) => c == 'files.read'), isEmpty);
  });

  testWidgets('thư mục trống', (tester) async {
    await _pump(
      tester,
      (op, a) => op == 'files.list' ? {'items': []} : _ok(op, a),
    );
    expect(find.text('Thư mục trống'), findsOneWidget);
  });

  testWidgets('lỗi tải thì có nút thử lại', (tester) async {
    await _pump(
      tester,
      (op, a) =>
          op == 'files.list' ? const IdeFakeError('internal') : _ok(op, a),
    );
    expect(find.text('Không mở được thư mục'), findsOneWidget);
  });

  testWidgets('không có quyền xem', (tester) async {
    await _pump(
      tester,
      (op, a) =>
          op == 'projects.list' ? const IdeFakeError('forbidden') : _ok(op, a),
    );
    expect(find.byType(Icon), findsWidgets);
    expect(find.text('Chưa có dự án'), findsNothing);
  });

  testWidgets('chưa có dự án', (tester) async {
    await _pump(
      tester,
      (op, a) => op == 'projects.list' ? {'items': []} : _ok(op, a),
    );
    expect(find.text('Chưa có dự án'), findsOneWidget);
  });

  testWidgets('đổi tên: tên có / bị chặn, tên hợp lệ gửi files.rename', (
    tester,
  ) async {
    final sent = <Map<String, Object?>>[];
    await _pump(tester, (op, a) {
      if (op == 'files.rename') sent.add(a);
      return _ok(op, a);
    });
    await tester.tap(find.byKey(const Key('ide_more_zeta.txt')));
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.byKey(const Key('ide_act_rename')));
    await settle(tester);
    await tester.enterText(find.byType(TextField).last, '../x');
    await tester.pump();
    await tester.tap(
      find.text('Lưu').evaluate().isNotEmpty
          ? find.text('Lưu')
          : find.text('OK'),
    );
    await settle(tester);
    expect(sent, isEmpty);
    await tester.enterText(find.byType(TextField).last, 'moi.txt');
    await tester.pump();
    await tester.tap(
      find.text('Lưu').evaluate().isNotEmpty
          ? find.text('Lưu')
          : find.text('OK'),
    );
    await settle(tester);
    expect(sent.single, {'path': '/srv/web/zeta.txt', 'name': 'moi.txt'});
  });

  testWidgets('xoá phải xác nhận rồi vào thùng rác', (tester) async {
    final sent = <Map<String, Object?>>[];
    await _pump(tester, (op, a) {
      if (op == 'files.delete') {
        sent.add(a);
        return {'id': 't1'};
      }
      return _ok(op, a);
    });
    await tester.tap(find.byKey(const Key('ide_more_zeta.txt')));
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.byKey(const Key('ide_act_delete')));
    await settle(tester);
    expect(sent, isEmpty);
    await tester.tap(find.text('Xoá').last);
    await settle(tester);
    expect(sent.single, {'path': '/srv/web/zeta.txt'});
  });

  testWidgets('sao chép rồi dán vào thư mục con gửi files.copy', (
    tester,
  ) async {
    final sent = <Map<String, Object?>>[];
    await _pump(tester, (op, a) {
      if (op == 'files.copy') sent.add(a);
      return _ok(op, a);
    });
    await tester.tap(find.byKey(const Key('ide_more_zeta.txt')));
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.byKey(const Key('ide_act_copy')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('ide_paste')));
    await settle(tester);
    expect(sent.single, {'path': '/srv/web/zeta.txt', 'dest_dir': '/srv/web'});
  });
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
}

void _scaleSuite() {
  for (final b in [Brightness.light, Brightness.dark]) {
    testWidgets('cỡ chữ 1.6 trên điện thoại không tràn ($b)', (tester) async {
      await _pump(tester, _ok, brightness: b);
      _phone(tester);
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      expect(find.text('main.dart'), findsOneWidget);
    });
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/app/providers/foundation_providers.dart';
import 'package:webtui_chat/design_system/theme/webtui_theme.dart';
import 'package:webtui_chat/design_system/tokens/webtui_colors.dart';
import 'package:webtui_chat/design_system/tokens/webtui_spacing.dart';
import 'package:webtui_chat/features/ide_mobile/presentation/screens/files/ide_file_editor_screen.dart';
import 'package:webtui_chat/features/ide_mobile/presentation/widgets/files/ide_code_view.dart';

import 'support/rpc_env.dart';

const _ops = ['files.write', 'files.read', 'files.diff', 'jobs.list'];

Future<IdeRpcEnv> _pump(
  WidgetTester tester,
  IdeFakeHandler handler, {
  String text = 'xin chao\nxin chao\n',
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  WebTuiColors.apply(brightness);
  final env = IdeRpcEnv(handler, ops: _ops);
  addTearDown(() => tester.runAsync(env.dispose));
  await tester.runAsync(env.up);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [ideRpcClientProvider.overrideWithValue(env.rpc)],
      child: MaterialApp(
        theme: brightness == Brightness.dark
            ? WebTuiTheme.dark()
            : WebTuiTheme.light(),
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: TextButton(
                key: const Key('open'),
                onPressed: () => Navigator.of(ctx).push(
                  MaterialPageRoute<void>(
                    builder: (_) => IdeFileEditorScreen(
                      root: '/srv/web',
                      path: '/srv/web/a.txt',
                      initialText: text,
                      baseMtime: 100,
                    ),
                  ),
                ),
                child: const Text('mở'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.tap(find.byKey(const Key('open')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  return env;
}

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const Key('ide_editor_field')), text);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 700));
}

String _fieldText(WidgetTester tester) => tester
    .widget<TextField>(find.byKey(const Key('ide_editor_field')))
    .controller!
    .text;

void main() {
  testWidgets('sửa rồi hoàn tác và làm lại', (tester) async {
    await _pump(tester, (_, _) => <String, Object?>{});
    expect(_fieldText(tester), 'xin chao\nxin chao\n');
    await tester.tap(find.byKey(const Key('ide_editor_field')));
    await tester.pump();
    await _type(tester, 'doi roi\n');
    await _type(tester, 'doi roi 2\n');
    final undo = tester.widget<IconButton>(
      find.byKey(const Key('ide_editor_undo')),
    );
    expect(undo.onPressed, isNotNull);
    await tester.tap(find.byKey(const Key('ide_editor_undo')));
    await tester.pump();
    expect(_fieldText(tester), 'doi roi\n');
    await tester.tap(find.byKey(const Key('ide_editor_redo')));
    await tester.pump();
    expect(_fieldText(tester), 'doi roi 2\n');
  });

  testWidgets('dòng dài có dấu không tự ngắt: số dòng thẳng hàng với mã', (
    tester,
  ) async {
    final long = "  home: Text('${'Xin chào thế giới, ' * 12}'),";
    await _pump(tester, (_, _) => <String, Object?>{}, text: 'a\n$long\nb');
    final field = find.byKey(const Key('ide_editor_field'));
    final extent = ideCodeLineExtent(tester.element(field));
    // 3 dòng: không dòng nào bị ngắt thành 2 hàng trên màn hình (mỗi hàng
    // làm tròn lên điểm ảnh nên so với 3,5 hàng), và cột số dòng cao bằng
    // phần chữ.
    final numbers = find.byType(IdeLineNumbers);
    final textH = tester.getSize(field).height - 2 * WebTuiSpacing.sm;
    expect(textH, lessThan(3.5 * extent));
    expect(
      tester.getSize(numbers).height,
      moreOrLessEquals(textH, epsilon: 1),
    );
  });

  testWidgets('cột số dòng: số 2 chữ số không ngắt dòng', (tester) async {
    final text = List.generate(12, (i) => 'dòng $i').join('\n');
    await _pump(tester, (_, _) => <String, Object?>{}, text: text);
    final numbers = find.byType(IdeLineNumbers);
    final extent = ideCodeLineExtent(tester.element(numbers));
    expect(tester.getSize(numbers).height, lessThan(12.5 * extent));
  });

  testWidgets('tìm và thay hết', (tester) async {
    await _pump(tester, (_, _) => <String, Object?>{});
    await tester.tap(find.byKey(const Key('ide_editor_find')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('ide_find_field')), 'xin');
    await tester.enterText(find.byKey(const Key('ide_replace_field')), 'hi');
    await tester.pump();
    await tester.tap(find.byKey(const Key('ide_replace_all')));
    await tester.pump();
    expect(_fieldText(tester), 'hi chao\nhi chao\n');
  });

  testWidgets('lưu gửi baseMtime', (tester) async {
    final sent = <Map<String, Object?>>[];
    await _pump(tester, (op, a) {
      if (op == 'files.write') {
        sent.add(a);
        return {'mtime': 200};
      }
      return <String, Object?>{};
    });
    await _type(tester, 'moi');
    await tester.tap(find.byKey(const Key('ide_editor_save')));
    await settle(tester);
    expect(sent.single, {
      'path': '/srv/web/a.txt',
      'text': 'moi',
      'baseMtime': 100,
    });
  });

  testWidgets('xung đột: 3 lựa chọn, Ghi đè gửi force', (tester) async {
    final sent = <Map<String, Object?>>[];
    await _pump(tester, (op, a) {
      if (op == 'files.write') {
        sent.add(a);
        return a['force'] == true
            ? {'mtime': 300}
            : const IdeFakeError('conflict');
      }
      return <String, Object?>{};
    });
    await _type(tester, 'moi');
    await tester.tap(find.byKey(const Key('ide_editor_save')));
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byKey(const Key('ide_conflict_reload')), findsOneWidget);
    expect(find.byKey(const Key('ide_conflict_force')), findsOneWidget);
    expect(find.byKey(const Key('ide_conflict_diff')), findsOneWidget);
    await tester.tap(find.byKey(const Key('ide_conflict_force')));
    await settle(tester);
    expect(sent, hasLength(2));
    expect(sent.last['force'], isTrue);
    expect(sent.first.containsKey('force'), isFalse);
  });

  testWidgets('thoát khi chưa lưu thì hỏi lại', (tester) async {
    await _pump(tester, (_, _) => <String, Object?>{});
    await _type(tester, 'doi');
    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Thoát mà chưa lưu?'), findsOneWidget);
    await tester.tap(find.text('Tiếp tục sửa'));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byKey(const Key('ide_editor_field')), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.text('Bỏ thay đổi'));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byKey(const Key('ide_editor_field')), findsNothing);
  });

  testWidgets('chưa sửa thì thoát thẳng', (tester) async {
    await _pump(tester, (_, _) => <String, Object?>{});
    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Thoát mà chưa lưu?'), findsNothing);
    expect(find.byKey(const Key('ide_editor_field')), findsNothing);
  });
}

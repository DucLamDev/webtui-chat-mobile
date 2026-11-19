import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/ide_mobile/application/ide_project_service.dart';
import 'package:webtui_chat/features/ide_mobile/domain/ide_deploy.dart';
import 'package:webtui_chat/features/ide_mobile/presentation/widgets/projects/ide_preview_view.dart';

import 'support/project_env.dart';
import 'support/rpc_env.dart';

Future<void> _show(WidgetTester t, Widget w, {double width = 300}) async {
  tester(t);
  await t.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: SingleChildScrollView(child: w),
          ),
        ),
      ),
    ),
  );
}

void tester(WidgetTester t) {
  t.view.physicalSize = const Size(800, 2000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

void main() {
  testWidgets('IdePathText: đường dẫn dài trong khung hẹp giữ tên tệp', (
    t,
  ) async {
    await _show(
      t,
      const IdePathText(
        'backend/internal/modules/ide_relay/application/rat_dai/notify.go',
      ),
      width: 160,
    );
    expect(find.text('notify.go'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('xoá / ghi đè hiện trước và có giới hạn riêng', (t) async {
    final files = [
      for (var i = 0; i < 300; i++) {'s': 'A', 'path': 'a/moi$i.php'},
      {'s': 'D', 'path': 'x/xoa-duy-nhat.php'},
      {'s': 'N', 'path': 'x/ghi-de.php'},
    ];
    final p = IdeDeployPreview.tryParse({
      ...previewResult(files: files),
      'total': 302,
    });
    await _show(t, IdePreviewView(preview: p!));
    expect(find.text('xoa-duy-nhat.php'), findsOneWidget);
    expect(find.text('ghi-de.php'), findsOneWidget);
    final d = t.getTopLeft(find.byKey(const Key('ide_preview_group_D'))).dy;
    final a = t.getTopLeft(find.byKey(const Key('ide_preview_group_A'))).dy;
    expect(d, lessThan(a));
  });

  test('clipDiff cắt dòng dài và tổng số dòng', () {
    final long = '+${'x' * 2000}';
    final (l1, c1) = IdePreviewView.clipDiff(long);
    expect(l1.single.length, 500);
    expect(c1, isTrue);
    final many = List.generate(1000, (i) => '+d$i').join('\n');
    final (l2, c2) = IdePreviewView.clipDiff(many);
    expect(l2.length, 400);
    expect(c2, isTrue);
    final (l3, c3) = IdePreviewView.clipDiff('+a\n-b');
    expect(l3.length, 2);
    expect(c3, isFalse);
  });

  testWidgets('diff quá dài: ghi đã cắt bớt', (t) async {
    final diff = List.generate(1000, (i) => '+d$i').join('\n');
    final p = IdeDeployPreview.tryParse({...previewResult(), 'diff': diff});
    await _show(t, IdePreviewView(preview: p!), width: 700);
    await t.tap(find.byKey(const Key('ide_preview_diff')));
    await t.pumpAndSettle();
    expect(
      find.textContaining('(đã cắt bớt)', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('waitJob chỉ giữ phần cuối của log', (t) async {
    final env = IdeRpcEnv((op, a) {
      return {
        'text': '${'a' * 300000}KET',
        'next': 1,
        'status': 'done',
        'done': true,
      };
    }, ops: ideProjectTestOps);
    addTearDown(() => t.runAsync(env.dispose));
    await t.runAsync(env.up);
    final out = await t.runAsync(() => IdeProjectService(env.rpc).waitJob('j'));
    expect(out!.log.length, ideWaitJobLogLimit);
    expect(out.log.endsWith('KET'), isTrue);
  });
}

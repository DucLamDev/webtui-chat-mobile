import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../preview/ide_web_preview.dart' as preview;

/// Điểm vào xem thử vẫn mở được mọi cảnh (không lỗi vẽ / thiếu thay thế).
void main() {
  testWidgets('mọi cảnh xem thử mở được', (tester) async {
    tester.view
      ..physicalSize = const Size(390, 1400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    preview.main();
    await tester.pump();
    for (final title in preview.previewScenes) {
      await tester.tap(find.text(title));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(tester.takeException(), isNull, reason: title);
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 11));
  });
}

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/design_system/tokens/webtui_text_scale.dart';

void main() {
  test(
    'cỡ chữ app 100%: giữ đúng như trước (chữ hệ thống giới hạn 85–135%)',
    () {
      const system = TextScaler.linear(2);
      expect(
        webTuiAppTextScaler(system, 1),
        system.clamp(minScaleFactor: 0.85, maxScaleFactor: 1.35),
      );
      expect(webTuiAppTextScaler(TextScaler.noScaling, 1).scale(10), 10);
    },
  );

  test('nhân thêm cỡ chữ người dùng chọn, tổng giới hạn 80–150%', () {
    expect(
      webTuiAppTextScaler(TextScaler.noScaling, 1.3).scale(10),
      closeTo(13, 1e-9),
    );
    expect(
      webTuiAppTextScaler(TextScaler.noScaling, 0.85).scale(10),
      closeTo(8.5, 1e-9),
    );
    // Máy đã đặt chữ lớn (1,2) × 130% = 156% → giữ 150% để bố cục không vỡ.
    expect(
      webTuiAppTextScaler(const TextScaler.linear(1.2), 1.3).scale(10),
      closeTo(15, 1e-9),
    );
    // Máy đặt chữ nhỏ (0,85) × 85% → không nhỏ hơn 80%.
    expect(
      webTuiAppTextScaler(const TextScaler.linear(0.85), 0.85).scale(10),
      closeTo(8, 1e-9),
    );
  });

  testWidgets('chữ trên màn phóng theo cỡ chữ app', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: webTuiAppTextScaler(TextScaler.noScaling, 1.3),
          ),
          child: child!,
        ),
        home: const Text('A', style: TextStyle(fontSize: 10)),
      ),
    );
    final paragraph = tester.renderObject<RenderParagraph>(find.text('A'));
    expect(paragraph.textScaler.scale(10), closeTo(13, 1e-9));
  });
}

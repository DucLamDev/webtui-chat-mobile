import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/ide_mobile/presentation/screens/tools/ide_tools_common.dart';
import 'package:webtui_chat/features/ide_mobile/presentation/widgets/ide_wb.dart';

/// Màn con tab Thêm gọn theo IDE web (đợt 2): nút nổi, chip chọn, lưới số liệu.
Widget _app(Widget child, {double width = 393, double textScale = 1}) =>
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 852),
          textScaler: TextScaler.linear(textScale),
        ),
        child: IdeWbTheme(
          child: Scaffold(
            body: Center(
              child: SizedBox(width: width - 32, child: child),
            ),
            floatingActionButton: FloatingActionButton.extended(
              key: const Key('fab'),
              onPressed: () {},
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Thêm việc'),
            ),
          ),
        ),
      ),
    );

List<Widget> _stats() => [
  for (var i = 0; i < 5; i++) ToolStat('Ô $i', '$i', key: Key('stat_$i')),
];

void main() {
  testWidgets('lưới số liệu 3 cột trên điện thoại thường', (t) async {
    await t.pumpWidget(_app(ToolStatGrid(children: _stats())));
    final y0 = t.getTopLeft(find.byKey(const Key('stat_0'))).dy;
    expect(t.getTopLeft(find.byKey(const Key('stat_2'))).dy, y0);
    expect(t.getTopLeft(find.byKey(const Key('stat_3'))).dy, greaterThan(y0));
    expect(t.takeException(), isNull);
  });

  testWidgets('chữ hệ thống 1,6: lưới 2 cột, không tràn', (t) async {
    await t.pumpWidget(
      _app(ToolStatGrid(children: _stats()), width: 320, textScale: 1.6),
    );
    final y0 = t.getTopLeft(find.byKey(const Key('stat_0'))).dy;
    expect(t.getTopLeft(find.byKey(const Key('stat_1'))).dy, y0);
    expect(t.getTopLeft(find.byKey(const Key('stat_2'))).dy, greaterThan(y0));
    expect(t.takeException(), isNull);
  });

  testWidgets('nút nổi có chữ cao 44 (không còn 56), lớn lên khi chữ to', (
    t,
  ) async {
    // Phần nhìn thấy (Material) cao 44; vùng bấm quanh nó vẫn ≥ 48.
    Finder face() => find
        .descendant(
          of: find.byKey(const Key('fab')),
          matching: find.byType(Material),
        )
        .first;
    await t.pumpWidget(_app(const SizedBox()));
    expect(t.getSize(face()).height, 44);
    expect(
      t.getSize(find.byKey(const Key('fab'))).height,
      greaterThanOrEqualTo(48),
    );
    await t.pumpWidget(_app(const SizedBox(), textScale: 3));
    expect(t.getSize(face()).height, greaterThan(44));
    expect(t.takeException(), isNull);
  });

  testWidgets('chip chọn: không dấu tích, không viền, chọn thì chữ tím', (
    t,
  ) async {
    await t.pumpWidget(
      _app(
        const Wrap(
          children: [
            ChoiceChip(label: Text('1h'), selected: true),
            ChoiceChip(label: Text('24h'), selected: false),
          ],
        ),
      ),
    );
    final ctx = t.element(find.text('1h'));
    final chip = Theme.of(ctx).chipTheme;
    expect(chip.showCheckmark, isFalse);
    expect(chip.side, BorderSide.none);
    expect(find.byIcon(Icons.check), findsNothing);
    final p = IdeWbPalette.of(ctx);
    final sel = t.widget<RichText>(
      find.descendant(of: find.text('1h'), matching: find.byType(RichText)),
    );
    final off = t.widget<RichText>(
      find.descendant(of: find.text('24h'), matching: find.byType(RichText)),
    );
    expect(sel.text.style?.color, p.accentInk);
    expect(off.text.style?.color, p.text);
  });
}

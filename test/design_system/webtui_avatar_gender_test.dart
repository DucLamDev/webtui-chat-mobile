import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/design_system/components/webtui_components.dart';
import 'package:webtui_chat/design_system/components/webtui_person_silhouette.dart';
import 'package:webtui_chat/design_system/icons/webtui_icons.dart';
import 'package:webtui_chat/design_system/tokens/webtui_colors.dart';

const _bgLight = Color(0xFFE4E6EB);
const _figLight = Color(0xFFBCC0C4);

void main() {
  tearDown(() => WebTuiColors.apply(Brightness.light));

  test('đọc giới tính: thiếu hoặc lạ là trung tính', () {
    expect(WebTuiAvatarGender.parse('male'), WebTuiAvatarGender.male);
    expect(WebTuiAvatarGender.parse('female'), WebTuiAvatarGender.female);
    expect(WebTuiAvatarGender.parse('unspecified'), WebTuiAvatarGender.neutral);
    expect(WebTuiAvatarGender.parse(null), WebTuiAvatarGender.neutral);
    expect(WebTuiAvatarGender.parse('khác'), WebTuiAvatarGender.neutral);
  });

  test('bộ chuyển path SVG dựng đúng hình (hộp bao, lệnh tương đối)', () {
    final box = webTuiPathFromSvg('M43 55h14v10H43z').getBounds();
    expect(box, const Rect.fromLTRB(43, 55, 57, 65));
    final body = webTuiPathFromSvg(
      'M12 100c0-20.5 15-34 32-35h12c17 1 32 14.5 32 35z',
    ).getBounds();
    expect(body.left, closeTo(12, 0.01));
    expect(body.right, closeTo(88, 0.01));
    expect(body.bottom, closeTo(100, 0.01));
    expect(body.top, closeTo(65, 0.5));
  });

  testWidgets('hình người đúng giới tính (đo điểm ảnh)', (tester) async {
    Future<ui.Image> render(WebTuiAvatarGender g, {bool dark = false}) async {
      WebTuiColors.apply(dark ? Brightness.dark : Brightness.light);
      final key = GlobalKey();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: RepaintBoundary(
              key: key,
              child: SizedBox.square(
                dimension: 100,
                child: WebTuiPersonSilhouette(gender: g),
              ),
            ),
          ),
        ),
      );
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      return (await tester.runAsync(boundary.toImage))!;
    }

    Future<Color> at(ui.Image image, int x, int y) async {
      final data = (await tester.runAsync(
        () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
      ))!;
      final i = (y * image.width + x) * 4;
      return Color.fromARGB(
        data.getUint8(i + 3),
        data.getUint8(i),
        data.getUint8(i + 1),
        data.getUint8(i + 2),
      );
    }

    final male = await render(WebTuiAvatarGender.male);
    final female = await render(WebTuiAvatarGender.female);
    final neutral = await render(WebTuiAvatarGender.neutral);
    // Đỉnh đầu: nam và nữ có hình, trung tính (đầu tròn thấp hơn) là nền.
    expect(await at(male, 50, 20), _figLight);
    expect(await at(female, 50, 17), _figLight);
    expect(await at(neutral, 50, 18), _bgLight);
    // Hai bên má: tóc dài của nữ phủ tới, nam và trung tính là nền.
    expect(await at(female, 27, 60), _figLight);
    expect(await at(male, 27, 60), _bgLight);
    expect(await at(neutral, 27, 60), _bgLight);
    // Cổ: chỉ nam có cổ riêng giữa đầu và vai.
    expect(await at(male, 50, 62), _figLight);
    // Vai và nền góc.
    for (final image in [male, female, neutral]) {
      expect(await at(image, 50, 90), _figLight);
      expect(await at(image, 3, 3), _bgLight);
    }

    final dark = await render(WebTuiAvatarGender.male, dark: true);
    expect(await at(dark, 3, 3), const Color(0xFF2A3546));
    expect(await at(dark, 50, 90), const Color(0xFF5D6B80));
  });

  testWidgets('avatar người chưa có ảnh vẽ hình người, không chữ viết tắt', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Column(
          children: [
            WebTuiAvatar(label: 'Lan Anh', gender: WebTuiAvatarGender.female),
            WebTuiAvatar(label: 'Nhóm Bán Hàng'),
            WebTuiAvatar(
              label: 'Kênh',
              icon: WebTuiIcons.messages,
              gender: null,
            ),
          ],
        ),
      ),
    );
    expect(find.byType(WebTuiPersonSilhouette), findsOneWidget);
    expect(find.text('LA'), findsNothing);
    // Nhóm / kênh / bot giữ chữ viết tắt hoặc biểu tượng như cũ.
    expect(find.text('NH'), findsOneWidget);
    expect(find.byIcon(WebTuiIcons.messages), findsOneWidget);
  });

  testWidgets('hình người không có dải màu bên dưới (mép tròn không lộ viền)', (
    tester,
  ) async {
    Gradient? gradientOf(Widget avatar) {
      final box = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byWidget(avatar),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      return (box.decoration as BoxDecoration).gradient;
    }

    const person = WebTuiAvatar(
      label: 'Lan Anh',
      gender: WebTuiAvatarGender.female,
    );
    const group = WebTuiAvatar(label: 'Nhóm Bán Hàng');
    await tester.pumpWidget(
      const MaterialApp(home: Column(children: [person, group])),
    );
    expect(gradientOf(person), isNull);
    // Nhóm / kênh vẫn giữ dải màu sau chữ viết tắt.
    expect(gradientOf(group), isNotNull);
  });

  testWidgets('ảnh lỗi thì rơi về hình người; có ảnh thì dùng ảnh', (
    tester,
  ) async {
    Widget build(Future<Uint8List?> Function() load) {
      return MaterialApp(
        home: WebTuiAvatarNetworkScope(
          apiBaseUri: Uri.parse('https://chat.example.test'),
          cacheKey: 'k${load.hashCode}',
          loadBytes: (uri, {required maxBytes, required allowPublicRequest}) =>
              load(),
          child: const WebTuiAvatar(
            label: 'Nam',
            imageUrl: '/a.png',
            gender: WebTuiAvatarGender.male,
          ),
        ),
      );
    }

    await tester.runAsync(() async {
      await tester.pumpWidget(build(() async => null));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    expect(find.byType(WebTuiPersonSilhouette), findsOneWidget);

    await tester.runAsync(() async {
      await tester.pumpWidget(build(() async => _png));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    expect(find.byType(RawImage), findsOneWidget);
    expect(find.byType(WebTuiPersonSilhouette), findsNothing);
  });
}

// PNG 1x1 hợp lệ.
final _png = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0xF8, 0xCF, 0xC0, 0xF0,
  0x1F, 0x00, 0x05, 0x00, 0x01, 0xFF, 0x89, 0x99, 0x3D, 0x1D, 0x00, 0x00,
  0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

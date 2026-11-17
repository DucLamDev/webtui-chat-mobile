import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/design_system/theme/webtui_theme.dart';
import 'package:webtui_chat/design_system/tokens/webtui_colors.dart';

import 'chat_room_body_harness.dart';

/// Khung chat kiểu Zalo: màu bong bóng, tương phản chữ, nền danh sách, ô soạn.
void main() {
  tearDown(() => WebTuiColors.apply(Brightness.light));

  double contrast(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final hi = la > lb ? la : lb;
    final lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }

  Color? bubbleColor(WidgetTester tester, String text) {
    final box = find
        .ancestor(
          of: find.text(text, findRichText: true),
          matching: find.byType(DecoratedBox),
        )
        .first;
    return ((tester.widget<DecoratedBox>(box)).decoration as BoxDecoration)
        .color;
  }

  TextStyle? textStyle(WidgetTester tester, String text) {
    final rich = tester.widget<RichText>(
      find.byWidgetPredicate(
        (w) => w is RichText && w.text.toPlainText() == text,
      ),
    );
    return rich.text.style;
  }

  Future<void> pumpBoth(WidgetTester tester, Brightness mode) async {
    WebTuiColors.apply(mode);
    await pumpChatRoom(
      tester,
      theme: mode == Brightness.dark ? WebTuiTheme.dark() : WebTuiTheme.light(),
      messages: [
        harnessText('a', 'tin mình', mine: true, at: harnessTime(9, 0)),
        harnessText('b', 'tin người kia', mine: false, at: harnessTime(9, 1)),
      ],
    );
  }

  testWidgets('nền sáng: mình xanh nhạt, người kia trắng, chữ màu thường', (
    tester,
  ) async {
    await pumpBoth(tester, Brightness.light);
    expect(bubbleColor(tester, 'tin mình'), const Color(0xFFD9E8FF));
    expect(bubbleColor(tester, 'tin người kia'), const Color(0xFFFFFFFF));
    expect(WebTuiColors.chatBackground, const Color(0xFFE2E9F1));
    for (final text in ['tin mình', 'tin người kia']) {
      expect(textStyle(tester, text)?.color, WebTuiColors.textPrimary);
    }
    expect(
      contrast(WebTuiColors.textPrimary, bubbleColor(tester, 'tin mình')!),
      greaterThanOrEqualTo(4.5),
    );
  });

  testWidgets('nền tối: mình xanh đậm vừa, người kia surface tối', (
    tester,
  ) async {
    await pumpBoth(tester, Brightness.dark);
    final mine = bubbleColor(tester, 'tin mình')!;
    final other = bubbleColor(tester, 'tin người kia')!;
    expect(mine, WebTuiColors.messageOutgoing);
    expect(other, WebTuiColors.messageIncoming);
    expect(mine, isNot(WebTuiColors.primary));
    for (final bg in [mine, other]) {
      expect(contrast(WebTuiColors.textPrimary, bg), greaterThanOrEqualTo(4.5));
      expect(
        contrast(WebTuiColors.textSecondary, bg),
        greaterThanOrEqualTo(4.5),
      );
    }
    // Liên kết trong bong bóng của mình (tối: trắng) vẫn đọc rõ.
    expect(contrast(Colors.white, mine), greaterThanOrEqualTo(4.5));
  });

  test('nền sáng: liên kết xanh đậm trên bong bóng của mình đạt 4.5:1', () {
    WebTuiColors.apply(Brightness.light);
    expect(
      contrast(WebTuiColors.primaryPressed, WebTuiColors.messageOutgoing),
      greaterThanOrEqualTo(4.5),
    );
  });

  testWidgets('ô soạn trống: ảnh + mic; có chữ: ẩn ảnh + mic, hiện nút gửi', (
    tester,
  ) async {
    await pumpChatRoom(tester, messages: const []);
    expect(find.byKey(const Key('chat_composer_image')), findsOneWidget);
    expect(find.byKey(const Key('chat_composer_mic')), findsOneWidget);
    expect(find.byKey(const Key('chat_composer_send')), findsNothing);
    expect(find.byKey(const Key('chat_composer_attach')), findsOneWidget);
    expect(find.byKey(const Key('chat_composer_emoji')), findsOneWidget);

    await pumpChatRoom(tester, messages: const [], draft: 'xin chào');
    expect(find.byKey(const Key('chat_composer_image')), findsNothing);
    expect(find.byKey(const Key('chat_composer_mic')), findsNothing);
    expect(find.byKey(const Key('chat_composer_send')), findsOneWidget);
    // Nút ⋯ thêm và emoji vẫn còn khi có chữ.
    expect(find.byKey(const Key('chat_composer_attach')), findsOneWidget);
    expect(find.byKey(const Key('chat_composer_emoji')), findsOneWidget);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/design_system/components/webtui_badges.dart';
import 'package:webtui_chat/design_system/components/webtui_list_items.dart';
import 'package:webtui_chat/design_system/theme/webtui_theme.dart';

void main() {
  testWidgets('huy hiệu không bị giãn trong Row cao 72', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 72,
            child: Row(
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [WebTuiUnreadBadge(count: 1)],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final size = tester.getSize(find.byType(WebTuiUnreadBadge));
    expect(size.height, lessThanOrEqualTo(24));
    expect(size.width, greaterThanOrEqualTo(18));
  });

  test('chữ huy hiệu: chat 1-1 tới 5+, nhóm tới 99+', () {
    expect(webTuiUnreadLabel(0), '');
    expect(webTuiUnreadLabel(-2), '');
    expect(webTuiUnreadLabel(5, max: webTuiUnreadMaxDirect), '5');
    expect(webTuiUnreadLabel(6, max: webTuiUnreadMaxDirect), '5+');
    expect(webTuiUnreadLabel(99), '99');
    expect(webTuiUnreadLabel(100), '99+');
  });

  testWidgets('mục hội thoại dùng trần được truyền vào', (tester) async {
    Widget item(int max) => MaterialApp(
      home: Scaffold(
        body: WebTuiConversationListItem(
          title: 'An',
          preview: 'Chào',
          timeLabel: '09:00',
          avatarLabel: 'An',
          unreadCount: 12,
          unreadMax: max,
        ),
      ),
    );
    await tester.pumpWidget(item(webTuiUnreadMaxDirect));
    expect(find.text('5+'), findsOneWidget);
    await tester.pumpWidget(item(webTuiUnreadMaxGroup));
    expect(find.text('12'), findsOneWidget);
  });

  testWidgets('dòng còn tin chưa đọc in đậm, đọc rồi trở về chữ thường', (
    tester,
  ) async {
    TextStyle style(String text) => tester.widget<Text>(find.text(text)).style!;
    Widget list(int unread) => MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            WebTuiConversationListItem(
              title: 'An',
              preview: 'Chào',
              timeLabel: '09:00',
              avatarLabel: 'An',
              unreadCount: unread,
            ),
            WebTuiChannelBotListItem(
              title: 'Bot',
              subtitle: 'Cuộc gọi đã kết thúc',
              icon: Icons.smart_toy_outlined,
              color: Colors.blue,
              unreadCount: unread,
            ),
          ],
        ),
      ),
    );

    await tester.pumpWidget(list(2));
    final unreadPreview = style('Chào');
    final unreadTime = style('09:00');
    final unreadBot = style('Cuộc gọi đã kết thúc');
    expect(unreadPreview.fontWeight, FontWeight.w700);
    expect(unreadTime.fontWeight, FontWeight.w700);
    expect(unreadBot.fontWeight, FontWeight.w700);

    await tester.pumpWidget(list(0));
    expect(style('Chào').fontWeight, isNot(FontWeight.w700));
    expect(style('09:00').fontWeight, isNot(FontWeight.w700));
    expect(style('Cuộc gọi đã kết thúc').fontWeight, isNot(FontWeight.w700));
    // Đổi cả màu, không chỉ độ đậm: chưa đọc thì chữ đậm màu hơn.
    expect(style('Chào').color, isNot(unreadPreview.color));
    expect(style('09:00').color, isNot(unreadTime.color));
    expect(style('Cuộc gọi đã kết thúc').color, isNot(unreadBot.color));
  });

  testWidgets('nút nổi có chữ là viên thuốc, chữ nằm trọn trong nút', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: WebTuiTheme.light(),
        home: Scaffold(
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () {},
            icon: const Icon(Icons.add_rounded),
            label: const Text('Ghi chú mới'),
          ),
        ),
      ),
    );
    final material = tester.widget<Material>(
      find
          .descendant(
            of: find.byType(FloatingActionButton),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(material.shape, isA<StadiumBorder>());
    final button = tester.getRect(find.byType(FloatingActionButton));
    final label = tester.getRect(find.text('Ghi chú mới'));
    expect(button.width, greaterThan(button.height));
    expect(button.contains(label.topLeft), isTrue);
    expect(button.contains(label.bottomRight), isTrue);
  });
}

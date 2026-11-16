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

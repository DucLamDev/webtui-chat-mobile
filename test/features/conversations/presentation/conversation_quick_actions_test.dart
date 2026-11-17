import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/conversations/presentation/widgets/conversation_quick_actions.dart';

void main() {
  const screen = Size(390, 844);
  const actions = [
    ConversationQuickAction.pin,
    ConversationQuickAction.markUnread,
    ConversationQuickAction.mute,
    ConversationQuickAction.hide,
    ConversationQuickAction.removeFromList,
    ConversationQuickAction.report,
  ];
  final height = conversationQuickActionsHeight(actions);

  RelativeRect place(Rect anchor) => conversationQuickActionsPosition(
    anchor: anchor,
    screen: screen,
    menuHeight: height,
    safeTop: 50,
    safeBottom: 120,
  );

  test('chiều cao: 6 dòng 48 + đệm + một kẻ trước nhóm xoá', () {
    expect(height, 6 * 48 + 12 + 9);
  });

  test('dòng ở trên: menu ngay dưới dòng, canh phải, cách mép 12', () {
    const row = Rect.fromLTWH(0, 200, 390, 72);
    final position = place(row);
    expect(position.top, closeTo(row.bottom, 8));
    expect(position.left, 390 - 240 - 12);
    expect(position.right, 12);
  });

  test('dòng gần đáy: menu bật lên ngay trên dòng', () {
    const row = Rect.fromLTWH(0, 640, 390, 72);
    final position = place(row);
    expect(position.top + height, closeTo(row.top, 8));
    expect(position.top, greaterThanOrEqualTo(50));
  });

  test('màn hẹp hơn menu: không đặt lệch ra ngoài mép trái', () {
    final position = conversationQuickActionsPosition(
      anchor: const Rect.fromLTWH(0, 100, 200, 72),
      screen: const Size(200, 844),
      menuHeight: height,
      safeTop: 0,
      safeBottom: 0,
    );
    expect(position.left, 12);
  });
}

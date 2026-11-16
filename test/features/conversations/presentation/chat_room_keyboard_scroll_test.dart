import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/conversations/domain/entities/chat_message.dart';

import 'chat_room_body_harness.dart';

/// Mở bàn phím làm khung danh sách co lại: tin cuối phải vẫn nằm ngay trên ô
/// soạn (không bị bàn phím / ô soạn che); đang đọc tin cũ thì giữ nguyên chỗ.
void main() {
  List<ChatMessage> manyMessages() => [
    for (var i = 1; i <= 40; i++)
      harnessText(
        '$i',
        i == 40 ? 'Tin cuối cùng' : 'Tin số $i',
        mine: i.isEven,
        at: harnessTime(9, i),
      ),
  ];

  Future<void> settleToBottom(WidgetTester tester) async {
    // Danh sách dựng dần nên độ dài ước lượng; kéo thêm tới khi chạm đáy.
    final list = find.byType(ListView).first;
    final controller = tester.widget<ListView>(list).controller!;
    for (var i = 0; i < 5; i++) {
      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pump();
    }
  }

  Future<void> openKeyboard(WidgetTester tester, double height) async {
    tester.view.viewInsets = FakeViewPadding(bottom: height);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('đang ở cuối: mở bàn phím thì tin cuối vẫn nằm trên ô soạn', (
    tester,
  ) async {
    addTearDown(tester.view.resetViewInsets);
    await pumpChatRoom(tester, messages: manyMessages());
    await settleToBottom(tester);
    final last = find.text('Tin cuối cùng', findRichText: true);
    expect(last, findsOneWidget);

    await openKeyboard(tester, 300);

    final composerTop = tester
        .getRect(find.byKey(const Key('chat_composer_surface')))
        .top;
    expect(composerTop, lessThanOrEqualTo(844 - 300));
    expect(last, findsOneWidget);
    expect(tester.getRect(last).bottom, lessThanOrEqualTo(composerTop));
    expect(tester.getRect(last).bottom, greaterThan(composerTop - 80));

    // Đóng bàn phím: vẫn ở cuối.
    await openKeyboard(tester, 0);
    final top = tester
        .getRect(find.byKey(const Key('chat_composer_surface')))
        .top;
    expect(
      tester.getRect(find.text('Tin cuối cùng', findRichText: true)).bottom,
      lessThan(top),
    );
  });

  testWidgets('đang đọc tin cũ: mở bàn phím không kéo danh sách', (
    tester,
  ) async {
    addTearDown(tester.view.resetViewInsets);
    await pumpChatRoom(tester, messages: manyMessages());
    final list = find.byType(ListView).first;
    await tester.drag(list, const Offset(0, 1500));
    await tester.pump(const Duration(milliseconds: 500));
    final controller = tester.widget<ListView>(list).controller!;
    final before = controller.offset;
    expect(before, lessThan(controller.position.maxScrollExtent - 400));

    await openKeyboard(tester, 300);

    expect(controller.offset, moreOrLessEquals(before));
  });
}

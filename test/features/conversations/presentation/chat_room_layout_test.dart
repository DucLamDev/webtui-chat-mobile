import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/design_system/icons/webtui_icons.dart';
import 'package:webtui_chat/features/conversations/domain/entities/call_session.dart';

import 'chat_room_body_harness.dart';

void main() {
  group('ô nhập', () {
    testWidgets('khung trống: nút mic; có chữ: đổi thành nút gửi', (
      tester,
    ) async {
      await pumpChatRoom(tester, messages: const []);
      expect(find.byKey(const Key('chat_composer_mic')), findsOneWidget);
      expect(find.byKey(const Key('chat_composer_send')), findsNothing);
      expect(find.byIcon(WebTuiIcons.mic), findsOneWidget);

      await pumpChatRoom(tester, messages: const [], draft: 'xin chào');
      expect(find.byKey(const Key('chat_composer_send')), findsOneWidget);
      expect(find.byKey(const Key('chat_composer_mic')), findsNothing);
      expect(find.byIcon(WebTuiIcons.send), findsOneWidget);
    });

    testWidgets('nút + bên trái, emoji nằm trong ô nhập', (tester) async {
      await pumpChatRoom(tester, messages: const []);
      final attach = tester.getCenter(
        find.byKey(const Key('chat_composer_attach')),
      );
      final input = tester.getRect(
        find.byKey(const Key('chat_composer_input')),
      );
      final emoji = tester.getCenter(
        find.byKey(const Key('chat_composer_emoji')),
      );
      final mic = tester.getCenter(find.byKey(const Key('chat_composer_mic')));

      expect(attach.dx, lessThan(input.left));
      expect(emoji.dx, greaterThan(input.right - 1));
      expect(mic.dx, greaterThan(emoji.dx));
      expect(find.text('Nhập tin nhắn...'), findsOneWidget);
    });
  });

  group('ảnh', () {
    testWidgets('giờ nằm trên ảnh, chú thích là bong bóng riêng bên dưới', (
      tester,
    ) async {
      final dir = Directory.systemTemp.createTempSync('chat_layout');
      addTearDown(() => dir.deleteSync(recursive: true));
      late String path;
      await tester.runAsync(() async {
        path = await writeFakePng(
          dir,
          'a',
          width: 400,
          height: 200,
          top: Colors.blue,
          bottom: Colors.indigo,
        );
      });
      await pumpChatRoom(
        tester,
        messages: [
          harnessMedia(
            'img',
            mine: true,
            at: harnessTime(13, 42),
            mime: 'image/png',
            name: 'a.png',
            localPath: path,
            body: 'Anh xem giúp em',
          ),
        ],
      );

      await settleImages(tester);
      final badge = find.byKey(const Key('message_media_time_badge'));
      expect(badge, findsOneWidget);
      expect(
        find.descendant(of: badge, matching: find.text('13:42')),
        findsOneWidget,
      );
      final image = find.byType(Image);
      expect(image, findsOneWidget);
      // Giờ nằm trong khung ảnh, góc dưới phải.
      final imageRect = tester.getRect(image);
      final badgeRect = tester.getRect(badge);
      expect(imageRect.contains(badgeRect.center), isTrue);
      expect(badgeRect.center.dx, greaterThan(imageRect.center.dx));
      expect(badgeRect.center.dy, greaterThan(imageRect.center.dy));
      // Chú thích: bong bóng chữ riêng, ngay dưới ảnh, không kèm giờ.
      final caption = find.text('Anh xem giúp em', findRichText: true);
      expect(caption, findsOneWidget);
      expect(
        tester.getTopLeft(caption).dy,
        greaterThanOrEqualTo(imageRect.bottom),
      );
      expect(find.text('13:42'), findsOneWidget);
    });
  });

  group('thẻ cuộc gọi', () {
    testWidgets('cuộc gọi nhỡ: chữ đỏ có giờ, nút gọi lại gọi đúng kiểu', (
      tester,
    ) async {
      CallMode? called;
      await pumpChatRoom(
        tester,
        messages: [
          harnessCall(
            'c1',
            mine: false,
            at: harnessTime(13, 46),
            status: 'missed',
            mode: 'video',
          ),
        ],
        onCall: (mode) => called = mode,
      );

      final label = find.text('Cuộc gọi nhỡ · 13:46');
      expect(label, findsOneWidget);
      expect(tester.widget<Text>(label).style?.color, const Color(0xFFE5322D));
      expect(find.byIcon(WebTuiIcons.phoneMissed), findsOneWidget);

      await tester.tap(find.byKey(const Key('chat_call_history_retry')));
      expect(called, CallMode.video);
    });

    testWidgets('cuộc gọi đi: "Cuộc gọi thoại đi · 17 giây" + nút gọi lại', (
      tester,
    ) async {
      CallMode? called;
      await pumpChatRoom(
        tester,
        messages: [
          harnessCall(
            'c2',
            mine: true,
            at: harnessTime(13, 41),
            status: 'ended',
            seconds: 17,
          ),
          harnessCall(
            'c3',
            mine: false,
            at: harnessTime(13, 50),
            status: 'ended',
            seconds: 125,
          ),
        ],
        onCall: (mode) => called = mode,
      );

      expect(find.text('Cuộc gọi thoại đi · 17 giây'), findsOneWidget);
      expect(find.text('Cuộc gọi thoại đến · 2 phút 5 giây'), findsOneWidget);
      await tester.tap(find.byKey(const Key('chat_call_history_retry')).first);
      expect(called, CallMode.audio);
    });
  });

  group('Đã xem', () {
    testWidgets('dòng "giờ · Đã xem" + biểu tượng chỉ dưới tin được xem', (
      tester,
    ) async {
      await pumpChatRoom(
        tester,
        messages: [
          harnessText('a', 'tin một', mine: true, at: harnessTime(13, 40)),
          harnessText('b', 'tin hai', mine: true, at: harnessTime(13, 42)),
          harnessText('c', 'tin ba', mine: true, at: harnessTime(13, 50)),
        ],
        seenMessageId: 'b',
      );

      expect(find.text('13:42 · Đã xem'), findsOneWidget);
      expect(find.byKey(const Key('chat_message_seen_icon')), findsOneWidget);
      expect(find.byKey(const Key('chat_message_status_line')), findsOneWidget);
    });

    testWidgets('không có seenMessageId (nhóm / bot): không hiện Đã xem', (
      tester,
    ) async {
      await pumpChatRoom(
        tester,
        messages: [
          harnessText('a', 'tin một', mine: true, at: harnessTime(13, 40)),
        ],
      );

      expect(find.textContaining('Đã xem'), findsNothing);
      expect(find.byKey(const Key('chat_message_seen_icon')), findsNothing);
    });

    testWidgets('tin lỗi gửi vẫn hiện "Chưa gửi được" như cũ', (tester) async {
      await pumpChatRoom(
        tester,
        messages: [
          harnessText(
            'f',
            'tin lỗi',
            mine: true,
            at: harnessTime(13, 40),
            metadata: const {'delivery_status': 'failed'},
          ),
        ],
      );

      expect(find.text('13:40 · Chưa gửi được'), findsOneWidget);
    });
  });

  group('đầu trang', () {
    testWidgets(
      '1-1: dòng "Đang hoạt động", gọi thoại / video, menu gom việc',
      (tester) async {
        CallMode? called;
        await pumpChatRoom(
          tester,
          messages: const [],
          withAppBar: true,
          onCall: (mode) => called = mode,
        );

        expect(find.text('Hồ Đức Lâm'), findsOneWidget);
        expect(find.text('Đang hoạt động'), findsOneWidget);
        await tester.tap(find.byKey(const Key('chat_room_call_video')));
        expect(called, CallMode.video);
        await tester.tap(find.byKey(const Key('chat_room_call_audio')));
        expect(called, CallMode.audio);

        await tester.tap(find.byKey(const Key('chat_room_more_menu')));
        await tester.pumpAndSettle();
        expect(find.text('Tìm tin nhắn'), findsOneWidget);
        expect(find.text('Báo cáo hoặc chặn người dùng'), findsOneWidget);
        expect(find.text('Công cụ làm việc'), findsOneWidget);
        expect(find.text('Chi tiết kênh'), findsOneWidget);
      },
    );

    testWidgets('máy chủ tắt cuộc gọi: không có nút gọi', (tester) async {
      await pumpChatRoom(
        tester,
        messages: const [],
        withAppBar: true,
        callsEnabled: false,
      );

      expect(find.byKey(const Key('chat_room_call_audio')), findsNothing);
      expect(find.byKey(const Key('chat_room_call_video')), findsNothing);
      expect(find.byKey(const Key('chat_room_more_menu')), findsOneWidget);
    });

    testWidgets('nhóm: dòng phụ là số thành viên', (tester) async {
      await pumpChatRoom(
        tester,
        messages: const [],
        withAppBar: true,
        directChat: false,
      );

      expect(find.text('2 thành viên'), findsOneWidget);
      expect(find.text('Đang hoạt động'), findsNothing);
    });

    testWidgets('chat bot thông báo: không nút gọi, menu chỉ còn tìm tin', (
      tester,
    ) async {
      await pumpChatRoom(
        tester,
        messages: const [],
        withAppBar: true,
        noticeBot: true,
        directChat: false,
      );

      expect(find.byKey(const Key('chat_room_call_audio')), findsNothing);
      await tester.tap(find.byKey(const Key('chat_room_more_menu')));
      await tester.pumpAndSettle();
      expect(find.text('Tìm tin nhắn'), findsOneWidget);
      expect(find.text('Công cụ làm việc'), findsNothing);
      expect(find.text('Chi tiết kênh'), findsNothing);
    });
  });

  testWidgets('nhãn ngày là viên bo tròn, tin chữ của mình nền xanh', (
    tester,
  ) async {
    await pumpChatRoom(
      tester,
      messages: [
        harnessText('a', 'tin mình', mine: true, at: harnessTime(9, 0)),
        harnessText('b', 'tin người kia', mine: false, at: harnessTime(9, 1)),
      ],
    );

    expect(find.text('Hôm nay'), findsOneWidget);
    final divider = tester.widget<DecoratedBox>(
      find.byKey(const Key('chat_day_divider')),
    );
    final decoration = divider.decoration as BoxDecoration;
    expect(decoration.borderRadius, BorderRadius.circular(20));

    Color? bubbleColor(String text) {
      final box = find
          .ancestor(
            of: find.text(text, findRichText: true),
            matching: find.byType(DecoratedBox),
          )
          .first;
      return ((tester.widget<DecoratedBox>(box)).decoration as BoxDecoration)
          .color;
    }

    expect(bubbleColor('tin mình'), const Color(0xFF0877F2));
    expect(bubbleColor('tin người kia'), const Color(0xFFFFFFFF));
  });
}

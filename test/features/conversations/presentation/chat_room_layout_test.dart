import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/design_system/icons/webtui_icons.dart';
import 'package:webtui_chat/design_system/tokens/webtui_colors.dart';
import 'package:webtui_chat/features/conversations/domain/entities/call_session.dart';
import 'package:webtui_chat/features/conversations/presentation/widgets/message_media_widgets.dart';

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
    testWidgets(
      'cuộc gọi nhỡ video: chữ đỏ, một biểu tượng, gọi lại bằng video',
      (tester) async {
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

        final title = find.text('Cuộc gọi nhỡ');
        expect(title, findsOneWidget);
        expect(
          tester.widget<Text>(title).style?.color,
          const Color(0xFFE5322D),
        );
        expect(find.text('Không trả lời · 13:46'), findsOneWidget);
        expect(find.byIcon(WebTuiIcons.videoOff), findsOneWidget);
        expect(find.byIcon(WebTuiIcons.phone), findsNothing);
        expect(find.text('Gọi lại'), findsOneWidget);
        final retry = tester.getSize(
          find.byKey(const Key('chat_call_history_retry')),
        );
        expect(retry.height, greaterThanOrEqualTo(44));

        await tester.tap(find.byKey(const Key('chat_call_history_retry')));
        expect(called, CallMode.video);
      },
    );

    testWidgets('cuộc gọi nhỡ thoại: biểu tượng nhỡ đỏ', (tester) async {
      await pumpChatRoom(
        tester,
        messages: [
          harnessCall(
            'c1',
            mine: false,
            at: harnessTime(13, 46),
            status: 'missed',
          ),
        ],
      );
      final icon = tester.widget<Icon>(find.byIcon(WebTuiIcons.phoneMissed));
      expect(icon.color, const Color(0xFFE5322D));
    });

    testWidgets(
      'thoại đi xanh dương, thoại đến xanh lá, mỗi thẻ một biểu tượng',
      (tester) async {
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
              seconds: 579,
            ),
          ],
          onCall: (mode) => called = mode,
        );

        expect(find.text('Cuộc gọi thoại đi'), findsOneWidget);
        expect(find.text('17 giây · 13:41'), findsOneWidget);
        expect(find.text('Cuộc gọi thoại đến'), findsOneWidget);
        expect(find.text('9 phút 39 giây · 13:50'), findsOneWidget);
        expect(
          tester.widget<Icon>(find.byIcon(WebTuiIcons.phoneOutgoing)).color,
          WebTuiColors.primary,
        );
        expect(
          tester.widget<Icon>(find.byIcon(WebTuiIcons.phoneIncoming)).color,
          WebTuiColors.accentGreen,
        );
        // Mỗi thẻ đúng một biểu tượng điện thoại (không lặp ở nút gọi lại).
        expect(find.byIcon(WebTuiIcons.phone), findsNothing);
        final card = find.byKey(const Key('chat_call_history_card'));
        expect(
          find.descendant(of: card.first, matching: find.byType(Icon)),
          findsOneWidget,
        );
        await tester.tap(
          find.byKey(const Key('chat_call_history_retry')).first,
        );
        expect(called, CallMode.audio);
      },
    );
  });

  group('ảnh ôm sát tỉ lệ', () {
    setUp(MessageMediaAspectCache.clear);

    Future<String> portrait(WidgetTester tester, Directory dir) async {
      late String path;
      await tester.runAsync(() async {
        path = await writeFakePng(
          dir,
          'p',
          width: 200,
          height: 400,
          top: Colors.teal,
          bottom: Colors.indigo,
        );
      });
      return path;
    }

    testWidgets('tin của mình: ô ảnh dọc sát mép phải, không chừa trống', (
      tester,
    ) async {
      final dir = Directory.systemTemp.createTempSync('chat_media');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = await portrait(tester, dir);
      await pumpChatRoom(
        tester,
        messages: [
          harnessMedia(
            'img',
            mine: true,
            at: harnessTime(13, 48),
            mime: 'image/png',
            name: 'p.png',
            localPath: path,
          ),
        ],
      );
      await settleImages(tester);
      final image = tester.getRect(find.byType(Image));
      // Tỉ lệ 1:2 -> cao tối đa, rộng = cao / 2 (không bị chừa trống hai bên).
      expect(image.width / image.height, closeTo(0.5, 0.02));
      expect(image.right, closeTo(390 - 16, 20));
      final badge = tester.getRect(
        find.byKey(const Key('message_media_time_badge')),
      );
      expect(image.contains(badge.center), isTrue);
      expect(badge.right, lessThanOrEqualTo(image.right));
      expect(image.right - badge.right, lessThan(16));
    });

    testWidgets('tin người khác: ô ảnh sát mép trái cột tin', (tester) async {
      final dir = Directory.systemTemp.createTempSync('chat_media');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = await portrait(tester, dir);
      await pumpChatRoom(
        tester,
        messages: [
          harnessMedia(
            'img',
            mine: false,
            at: harnessTime(13, 48),
            mime: 'image/png',
            name: 'p.png',
            localPath: path,
          ),
        ],
      );
      await settleImages(tester);
      final image = tester.getRect(find.byType(Image));
      expect(image.left, lessThan(24));
      expect(image.width / image.height, closeTo(0.5, 0.02));
    });

    testWidgets('lưu tỉ lệ theo mã tệp sau khi giải mã', (tester) async {
      final dir = Directory.systemTemp.createTempSync('chat_media');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = await portrait(tester, dir);
      expect(MessageMediaAspectCache.get('file-img'), isNull);
      await pumpChatRoom(
        tester,
        messages: [
          harnessMedia(
            'img',
            mine: true,
            at: harnessTime(13, 48),
            mime: 'image/png',
            name: 'p.png',
            localPath: path,
          ),
        ],
      );
      await settleImages(tester);
      expect(MessageMediaAspectCache.get('file-img'), closeTo(0.5, 0.001));
    });

    test('hộp ôm tỉ lệ, kẹp [0.5, 2.0], bộ đệm có giới hạn', () {
      final tall = fitMessageMediaBox(
        ratio: 0.2,
        maxWidth: 258,
        maxHeight: 286,
      );
      expect(tall.height, 286);
      expect(tall.width, closeTo(143, 0.01));
      final wide = fitMessageMediaBox(ratio: 4, maxWidth: 258, maxHeight: 286);
      expect(wide.width, 258);
      expect(wide.height, closeTo(129, 0.01));
      final unknown = fitMessageMediaBox(
        ratio: messageMediaUnknownRatio,
        maxWidth: 258,
        maxHeight: 286,
      );
      expect(unknown.width / unknown.height, closeTo(4 / 3, 0.001));
      for (var i = 0; i < MessageMediaAspectCache.maxEntries + 50; i++) {
        MessageMediaAspectCache.put('k$i', 1.5);
      }
      expect(
        MessageMediaAspectCache.length,
        MessageMediaAspectCache.maxEntries,
      );
      expect(MessageMediaAspectCache.get('k0'), isNull);
      expect(
        MessageMediaAspectCache.get(
          'k${MessageMediaAspectCache.maxEntries + 49}',
        ),
        1.5,
      );
    });
  });

  group('bình chọn', () {
    Future<void> openPlus(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('chat_composer_attach')));
      await tester.pumpAndSettle();
    }

    testWidgets('nhóm / kênh: bảng + có "Tạo bình chọn"', (tester) async {
      await pumpChatRoom(tester, messages: const []);
      await openPlus(tester);
      expect(find.text('Tạo bình chọn'), findsOneWidget);
      expect(find.text('Hẹn giờ gửi'), findsOneWidget);
    });

    testWidgets('chat 1-1 (kể cả bot): bảng + không có "Tạo bình chọn"', (
      tester,
    ) async {
      await pumpChatRoom(tester, messages: const [], allowPolls: false);
      await openPlus(tester);
      expect(find.text('Tạo bình chọn'), findsNothing);
      expect(find.text('Hẹn giờ gửi'), findsOneWidget);
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

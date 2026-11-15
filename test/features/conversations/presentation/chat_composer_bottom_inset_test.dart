import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/design_system/theme/webtui_theme.dart';

import 'chat_room_body_harness.dart';

/// Ô nhập tin dính đáy: không còn dải trống thừa dưới hàng nhập. Trước đây
/// thân màn bọc `SafeArea` cộng nguyên vùng an toàn đáy (34 trên iPhone) dưới
/// ô nhập, cộng thêm 8 đệm của ô nhập.
void main() {
  Future<({Rect mic, Rect surface})> pumpWithInsets(
    WidgetTester tester, {
    required TargetPlatform platform,
    required double safeBottom,
    double keyboard = 0,
  }) async {
    // Bàn phím mở: hệ điều hành báo padding đáy 0, viewPadding giữ vùng an
    // toàn, viewInsets là chiều cao bàn phím.
    tester.view.padding = FakeViewPadding(
      bottom: keyboard > 0 ? 0 : safeBottom,
    );
    tester.view.viewPadding = FakeViewPadding(bottom: safeBottom);
    tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);
    addTearDown(tester.view.resetViewInsets);
    await pumpChatRoom(
      tester,
      theme: WebTuiTheme.light().copyWith(platform: platform),
      messages: [
        harnessText('1', 'Chào anh', mine: false, at: harnessTime(9, 1)),
      ],
    );
    return (
      mic: tester.getRect(find.byKey(const Key('chat_composer_mic'))),
      surface: tester.getRect(find.byKey(const Key('chat_composer_surface'))),
    );
  }

  for (final (name, platform, safeBottom, gap) in [
    // iPhone: sát ngay trên thanh home (bớt 12 phần thừa của vùng an toàn).
    ('iPhone thanh home 34', TargetPlatform.iOS, 34.0, 22.0),
    ('iPhone không vùng an toàn', TargetPlatform.iOS, 0.0, 8.0),
    // Android: đúng vùng thanh điều hướng, không đè nút hệ thống.
    ('Android không vùng an toàn', TargetPlatform.android, 0.0, 8.0),
    ('Android cử chỉ 24', TargetPlatform.android, 24.0, 24.0),
    ('Android 3 nút 48', TargetPlatform.android, 48.0, 48.0),
  ]) {
    testWidgets('$name: hàng nhập cách đáy $gap, nền trắng tới mép', (
      tester,
    ) async {
      final rects = await pumpWithInsets(
        tester,
        platform: platform,
        safeBottom: safeBottom,
      );
      expect(844 - rects.mic.bottom, moreOrLessEquals(gap));
      // Không đè thanh home / nút hệ thống.
      expect(
        844 - rects.mic.bottom,
        greaterThanOrEqualTo(safeBottom > 0 ? safeBottom - 12 : 0),
      );
      // Nền trắng ô nhập phủ cả vùng an toàn: không còn dải màu nền chat.
      expect(rects.surface.bottom, moreOrLessEquals(844));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('bàn phím mở: ô nhập sát bàn phím, không cộng vùng an toàn', (
    tester,
  ) async {
    final rects = await pumpWithInsets(
      tester,
      platform: TargetPlatform.iOS,
      safeBottom: 34,
      keyboard: 300,
    );
    expect(rects.surface.bottom, moreOrLessEquals(844 - 300));
    expect(844 - 300 - rects.mic.bottom, moreOrLessEquals(8));
  });
}

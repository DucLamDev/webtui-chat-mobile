import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/conversations/domain/entities/conversation_summary.dart';
import 'package:webtui_chat/features/conversations/presentation/widgets/quick_channel_strip.dart';

void main() {
  ConversationSummary channel(String slug, String title, {int unread = 0}) {
    return ConversationSummary(
      id: slug,
      workspaceId: 'ws-1',
      channelId: slug,
      kind: ConversationKind.channel,
      title: title,
      preview: '',
      updatedAt: DateTime(2026, 11, 14),
      slug: slug,
      isAutomation: true,
      unreadCount: unread,
    );
  }

  final channels = [
    channel('order', 'Đơn hàng', unread: 2),
    channel('renew', 'Gia hạn', unread: 3),
    channel('ticket', 'Ticket'),
  ];

  Future<List<String>> pumpStrip(
    WidgetTester tester, {
    Widget Function(Widget strip)? wrap,
  }) async {
    final tapped = <String>[];
    final strip = QuickChannelStrip(
      channels: channels,
      onTap: (c) => tapped.add(c.id),
      onShowAll: () => tapped.add('xem-tat-ca'),
    );
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: wrap == null ? strip : wrap(strip))),
    );
    return tapped;
  }

  testWidgets('mặc định thu gọn: chỉ một dòng, cộng dồn tin chưa đọc', (
    tester,
  ) async {
    await pumpStrip(tester);

    expect(find.text('Nghiệp vụ'), findsOneWidget);
    expect(find.text('3 kênh'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    expect(find.text('Đơn hàng'), findsNothing);
    expect(find.text('Xem tất cả'), findsNothing);
  });

  testWidgets('bấm dòng Nghiệp vụ thì mở ra, bấm lần nữa thì thu lại', (
    tester,
  ) async {
    final tapped = await pumpStrip(tester);

    await tester.tap(find.byKey(const ValueKey('quick-channel-toggle')));
    await tester.pumpAndSettle();
    expect(find.text('Đơn hàng'), findsOneWidget);
    expect(find.text('Ticket'), findsOneWidget);
    // Mở ra thì huy hiệu nằm trên từng kênh, không cộng dồn lên tiêu đề.
    expect(find.text('5'), findsNothing);

    await tester.tap(find.text('Gia hạn'));
    await tester.tap(find.text('Xem tất cả'));
    expect(tapped, ['renew', 'xem-tat-ca']);

    await tester.tap(find.byKey(const ValueKey('quick-channel-toggle')));
    await tester.pumpAndSettle();
    expect(find.text('Đơn hàng'), findsNothing);
  });

  testWidgets('nhớ trạng thái mở khi dải bị dựng lại', (tester) async {
    final bucket = PageStorageBucket();
    Widget wrap(Widget strip) => PageStorage(bucket: bucket, child: strip);

    await pumpStrip(tester, wrap: wrap);
    await tester.tap(find.byKey(const ValueKey('quick-channel-toggle')));
    await tester.pumpAndSettle();

    // Dải biến mất (đổi bộ lọc) rồi hiện lại.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PageStorage(bucket: bucket, child: const SizedBox()),
        ),
      ),
    );
    await pumpStrip(tester, wrap: wrap);
    expect(find.text('Đơn hàng'), findsOneWidget);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/design_system/theme/webtui_theme.dart';
import 'package:webtui_chat/features/conversations/domain/entities/business_channel_catalog.dart';
import 'package:webtui_chat/features/conversations/domain/entities/conversation_summary.dart';
import 'package:webtui_chat/features/conversations/presentation/widgets/business_channel_grid.dart';

void main() {
  testWidgets('tab Nghiệp vụ hiện lưới chia nhóm, Đơn hàng đứng đầu', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final tapped = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        theme: WebTuiTheme.light(),
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              BusinessChannelSections(
                channels: [
                  // Thứ tự A→Z như máy chủ trả (cùng giờ tạo).
                  for (final definition in [
                    ...businessChannelCatalog,
                  ]..sort((a, b) => a.defaultTitle.compareTo(b.defaultTitle)))
                    _channel(definition),
                ],
                onTap: (channel) => tapped.add(channel.slug!),
              ),
            ],
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    final headers = [
      for (final group in [
        BusinessChannelGroup.sales,
        BusinessChannelGroup.customerSupport,
        BusinessChannelGroup.monitoring,
        BusinessChannelGroup.engineering,
      ])
        tester.getTopLeft(find.byKey(ValueKey('business_group_${group.name}'))),
    ];
    for (var index = 1; index < headers.length; index++) {
      expect(headers[index].dy, greaterThan(headers[index - 1].dy));
    }

    final orders = tester.getTopLeft(find.text('Đơn hàng'));
    final renew = tester.getTopLeft(find.text('Gia hạn'));
    expect(orders.dy, renew.dy, reason: 'cùng hàng đầu nhóm Bán hàng');
    expect(orders.dx, lessThan(renew.dx));
    // Bốn ô một hàng trên điện thoại: Doanh thu vẫn ở hàng đầu.
    expect(tester.getTopLeft(find.text('Doanh thu')).dy, orders.dy);
    // Cả 15 kênh nằm gọn trong một màn hình, không phải cuộn.
    expect(tester.getBottomLeft(find.text('Nhật ký API')).dy, lessThan(844));

    await tester.tap(find.text('Gia hạn'));
    expect(tapped, ['gia-han']);
  });
}

ConversationSummary _channel(BusinessChannelDefinition definition) {
  return ConversationSummary(
    id: definition.slug,
    workspaceId: 'ws-1',
    channelId: definition.slug,
    kind: ConversationKind.channel,
    title: definition.defaultTitle,
    preview: '',
    updatedAt: DateTime.utc(2026, 11, 2, 17, 29),
    unreadCount: definition.slug == 'canh-bao' ? 2 : 0,
    privateSessionMode: true,
    isAutomation: true,
    slug: definition.slug,
  );
}

import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/conversations/domain/entities/business_channel_catalog.dart';
import 'package:webtui_chat/features/conversations/domain/entities/conversation_summary.dart';

void main() {
  test('15 kênh mặc định chia 4 nhóm, Đơn hàng và Gia hạn đứng đầu', () {
    final channels = [
      for (final definition in businessChannelCatalog.reversed)
        _channel(definition.defaultTitle, slug: definition.slug),
    ];

    final sections = groupBusinessChannels(channels);

    expect(sections.map((section) => section.group), [
      BusinessChannelGroup.sales,
      BusinessChannelGroup.customerSupport,
      BusinessChannelGroup.monitoring,
      BusinessChannelGroup.engineering,
    ]);
    expect(_titles(sections.first.channels), [
      'Đơn hàng',
      'Gia hạn',
      'Kế toán',
      'Doanh thu',
    ]);
    expect(_titles(sections[1].channels), ['Ticket', 'Hỗ trợ']);
    expect(_titles(sections[2].channels), [
      'Cảnh báo',
      'Cảnh báo máy chủ',
      'Giám sát VPS',
      'Giám sát Proxy',
      'Sự cố',
      'Bảo mật',
    ]);
    expect(_titles(sections[3].channels), [
      'Tự động hóa',
      'Webhook',
      'Nhật ký API',
    ]);
  });

  test('nhận kênh theo slug kể cả khi quản trị đổi tên', () {
    final renamed = _channel('Đơn VPS / Proxy', slug: 'orders');

    expect(businessChannelDefinitionOf(renamed)?.slug, 'orders');
    expect(
      businessChannelDefinitionOf(renamed)?.group,
      BusinessChannelGroup.sales,
    );
  });

  test('máy chủ cũ chưa trả slug: nhận theo tên mặc định', () {
    expect(businessChannelDefinitionOf(_channel('Gia hạn'))?.slug, 'gia-han');
    expect(
      businessChannelDefinitionOf(_channel('giám sát vps'))?.slug,
      'monitor-vps',
    );
  });

  test('kênh bot ngoài danh mục vào nhóm Khác, xếp cuối theo tên', () {
    final sections = groupBusinessChannels([
      _channel('Zalo OA', slug: 'zalo'),
      _channel('Bot báo giá'),
      _channel('Gia hạn', slug: 'gia-han'),
    ]);

    expect(sections.map((section) => section.group), [
      BusinessChannelGroup.sales,
      BusinessChannelGroup.other,
    ]);
    expect(_titles(sections.last.channels), ['Bot báo giá', 'Zalo OA']);
  });

  test('không có kênh thì không có nhóm nào', () {
    expect(groupBusinessChannels(const []), isEmpty);
  });
}

List<String> _titles(List<ConversationSummary> channels) {
  return channels.map((channel) => channel.title).toList();
}

ConversationSummary _channel(String title, {String? slug}) {
  final id = slug ?? title;
  return ConversationSummary(
    id: id,
    workspaceId: 'ws-1',
    channelId: id,
    kind: ConversationKind.channel,
    title: title,
    preview: '',
    updatedAt: DateTime.utc(2026, 11, 2, 17, 29),
    isAutomation: true,
    slug: slug,
  );
}

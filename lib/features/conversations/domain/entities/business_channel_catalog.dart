import 'conversation_summary.dart';

/// Nhóm kênh nghiệp vụ (kênh bot) để hộp thư hiện gọn theo việc thay vì một
/// danh sách dài xếp theo tên.
enum BusinessChannelGroup {
  sales('Bán hàng'),
  customerSupport('Hỗ trợ khách'),
  monitoring('Giám sát & cảnh báo'),
  engineering('Kỹ thuật'),
  other('Khác');

  const BusinessChannelGroup(this.label);

  final String label;
}

final class BusinessChannelDefinition {
  const BusinessChannelDefinition({
    required this.slug,
    required this.defaultTitle,
    required this.group,
  });

  /// Mã kênh máy chủ đặt sẵn, không đổi khi quản trị đổi tên kênh.
  final String slug;

  /// Tên mặc định, dùng để nhận ra kênh khi máy chủ cũ chưa trả `slug`.
  final String defaultTitle;
  final BusinessChannelGroup group;
}

/// Thứ tự cố định của các kênh nghiệp vụ máy chủ tạo sẵn: bán hàng trước (đơn
/// hàng, gia hạn...), rồi hỗ trợ khách, giám sát / cảnh báo, kỹ thuật.
const businessChannelCatalog = <BusinessChannelDefinition>[
  BusinessChannelDefinition(
    slug: 'orders',
    defaultTitle: 'Đơn hàng',
    group: BusinessChannelGroup.sales,
  ),
  BusinessChannelDefinition(
    slug: 'gia-han',
    defaultTitle: 'Gia hạn',
    group: BusinessChannelGroup.sales,
  ),
  BusinessChannelDefinition(
    slug: 'ke-toan',
    defaultTitle: 'Kế toán',
    group: BusinessChannelGroup.sales,
  ),
  BusinessChannelDefinition(
    slug: 'billing',
    defaultTitle: 'Doanh thu',
    group: BusinessChannelGroup.sales,
  ),
  BusinessChannelDefinition(
    slug: 'ticket',
    defaultTitle: 'Ticket',
    group: BusinessChannelGroup.customerSupport,
  ),
  BusinessChannelDefinition(
    slug: 'support',
    defaultTitle: 'Hỗ trợ',
    group: BusinessChannelGroup.customerSupport,
  ),
  BusinessChannelDefinition(
    slug: 'canh-bao',
    defaultTitle: 'Cảnh báo',
    group: BusinessChannelGroup.monitoring,
  ),
  BusinessChannelDefinition(
    slug: 'server-alert',
    defaultTitle: 'Cảnh báo máy chủ',
    group: BusinessChannelGroup.monitoring,
  ),
  BusinessChannelDefinition(
    slug: 'monitor-vps',
    defaultTitle: 'Giám sát VPS',
    group: BusinessChannelGroup.monitoring,
  ),
  BusinessChannelDefinition(
    slug: 'monitor-proxy',
    defaultTitle: 'Giám sát Proxy',
    group: BusinessChannelGroup.monitoring,
  ),
  BusinessChannelDefinition(
    slug: 'incidents',
    defaultTitle: 'Sự cố',
    group: BusinessChannelGroup.monitoring,
  ),
  BusinessChannelDefinition(
    slug: 'security',
    defaultTitle: 'Bảo mật',
    group: BusinessChannelGroup.monitoring,
  ),
  BusinessChannelDefinition(
    slug: 'automation',
    defaultTitle: 'Tự động hóa',
    group: BusinessChannelGroup.engineering,
  ),
  BusinessChannelDefinition(
    slug: 'webhooks',
    defaultTitle: 'Webhook',
    group: BusinessChannelGroup.engineering,
  ),
  BusinessChannelDefinition(
    slug: 'api-logs',
    defaultTitle: 'Nhật ký API',
    group: BusinessChannelGroup.engineering,
  ),
];

/// Định nghĩa của kênh theo `slug`; máy chủ cũ không trả `slug` thì so theo tên
/// mặc định. Kênh bot khác (quản trị tự tạo) trả `null`.
BusinessChannelDefinition? businessChannelDefinitionOf(
  ConversationSummary channel,
) {
  final slug = channel.slug?.trim().toLowerCase() ?? '';
  if (slug.isNotEmpty) {
    for (final definition in businessChannelCatalog) {
      if (definition.slug == slug) return definition;
    }
    return null;
  }
  final title = channel.title.trim().toLowerCase();
  for (final definition in businessChannelCatalog) {
    if (definition.defaultTitle.toLowerCase() == title) return definition;
  }
  return null;
}

/// Thứ tự hiển thị kênh nghiệp vụ: theo danh mục cố định, kênh ngoài danh mục
/// xếp sau theo tên. Không phụ thuộc tin mới / chưa đọc để vị trí kênh ổn định.
int compareBusinessChannels(
  ConversationSummary left,
  ConversationSummary right,
) {
  final byRank = _rank(left).compareTo(_rank(right));
  if (byRank != 0) return byRank;
  return left.title.toLowerCase().compareTo(right.title.toLowerCase());
}

int _rank(ConversationSummary channel) {
  final definition = businessChannelDefinitionOf(channel);
  return definition == null
      ? businessChannelCatalog.length
      : businessChannelCatalog.indexOf(definition);
}

final class BusinessChannelSection {
  const BusinessChannelSection({required this.group, required this.channels});

  final BusinessChannelGroup group;
  final List<ConversationSummary> channels;
}

/// Chia kênh nghiệp vụ theo nhóm (theo thứ tự nhóm), mỗi nhóm đã xếp theo
/// [compareBusinessChannels]; nhóm rỗng bị bỏ.
List<BusinessChannelSection> groupBusinessChannels(
  Iterable<ConversationSummary> channels,
) {
  final byGroup = <BusinessChannelGroup, List<ConversationSummary>>{};
  for (final channel in channels) {
    final group =
        businessChannelDefinitionOf(channel)?.group ??
        BusinessChannelGroup.other;
    (byGroup[group] ??= []).add(channel);
  }
  return [
    for (final group in BusinessChannelGroup.values)
      if (byGroup[group] case final items?)
        BusinessChannelSection(
          group: group,
          channels: items..sort(compareBusinessChannels),
        ),
  ];
}

import 'package:flutter/material.dart';

import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_radii.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../../domain/entities/business_channel_catalog.dart';
import '../../domain/entities/conversation_summary.dart';

/// Tab Nghiệp vụ: mỗi nhóm (Bán hàng, Hỗ trợ khách...) một tiêu đề và lưới ô
/// nhỏ thay cho danh sách dài; 15 kênh mặc định gần vừa một màn hình điện thoại.
/// Dùng làm một sliver trong `CustomScrollView`.
class BusinessChannelSections extends StatelessWidget {
  const BusinessChannelSections({
    required this.channels,
    required this.onTap,
    super.key,
  });

  final List<ConversationSummary> channels;
  final ValueChanged<ConversationSummary> onTap;

  @override
  Widget build(BuildContext context) {
    return SliverMainAxisGroup(
      slivers: [
        for (final section in groupBusinessChannels(channels)) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                WebTuiSpacing.lg,
                WebTuiSpacing.md,
                WebTuiSpacing.lg,
                WebTuiSpacing.xs,
              ),
              child: Text(
                section.group.label,
                key: ValueKey('business_group_${section.group.name}'),
                style: const TextStyle(
                  color: WebTuiColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: WebTuiSpacing.md),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 96,
                mainAxisExtent: 92,
                crossAxisSpacing: WebTuiSpacing.xs,
              ),
              delegate: SliverChildBuilderDelegate((context, index) {
                final channel = section.channels[index];
                return BusinessChannelTile(
                  channel: channel,
                  width: double.infinity,
                  onTap: () => onTap(channel),
                );
              }, childCount: section.channels.length),
            ),
          ),
        ],
      ],
    );
  }
}

/// Một ô kênh nghiệp vụ: biểu tượng riêng, tên, huy hiệu tin chưa đọc.
class BusinessChannelTile extends StatelessWidget {
  const BusinessChannelTile({
    required this.channel,
    required this.onTap,
    this.width = 76,
    super.key,
  });

  final ConversationSummary channel;
  final VoidCallback onTap;
  final double width;

  @override
  Widget build(BuildContext context) {
    final unread = channel.unreadCount;
    return Semantics(
      button: true,
      excludeSemantics: true,
      label: unread > 0
          ? '${channel.title}, $unread tin chưa đọc'
          : channel.title,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(WebTuiRadii.md),
        child: SizedBox(
          width: width,
          child: Column(
            children: [
              const SizedBox(height: WebTuiSpacing.xs),
              Badge(
                isLabelVisible: unread > 0,
                backgroundColor: WebTuiColors.danger,
                label: Text(unread > 99 ? '99+' : '$unread'),
                child: CircleAvatar(
                  radius: 24,
                  backgroundColor: WebTuiColors.primarySoft,
                  child: Icon(
                    businessChannelIcon(channel),
                    color: WebTuiColors.primary,
                  ),
                ),
              ),
              const SizedBox(height: WebTuiSpacing.xs),
              Text(
                channel.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.2,
                  color: WebTuiColors.textPrimary,
                  fontWeight: unread > 0 ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Biểu tượng riêng cho từng kênh nghiệp vụ để nhận ra nhanh; kênh ngoài danh
/// mục thì đoán theo tên (gia hạn, order, proxy, VPS...).
IconData businessChannelIcon(ConversationSummary channel) {
  final known = switch (businessChannelDefinitionOf(channel)?.slug) {
    'orders' => Icons.shopping_bag_outlined,
    'gia-han' => Icons.autorenew_rounded,
    'ke-toan' => Icons.account_balance_wallet_outlined,
    'billing' => Icons.trending_up_rounded,
    'ticket' => Icons.confirmation_number_outlined,
    'support' => Icons.support_agent_rounded,
    'canh-bao' => Icons.notifications_active_outlined,
    'server-alert' => Icons.dns_rounded,
    'monitor-vps' => Icons.monitor_heart_outlined,
    'monitor-proxy' => Icons.vpn_lock_rounded,
    'incidents' => Icons.warning_amber_rounded,
    'security' => Icons.shield_outlined,
    'automation' => Icons.smart_toy_outlined,
    'webhooks' => Icons.webhook_rounded,
    'api-logs' => Icons.receipt_long_outlined,
    _ => null,
  };
  if (known != null) return known;
  final text = channel.title.toLowerCase();
  bool has(List<String> words) => words.any(text.contains);
  if (has(['gia hạn', 'gia han', 'renew'])) return Icons.autorenew_rounded;
  if (has(['order', 'đơn', 'mua'])) return Icons.shopping_bag_outlined;
  if (has(['proxy'])) return Icons.vpn_lock_rounded;
  if (has(['vps', 'server', 'máy chủ'])) return Icons.dns_rounded;
  if (has(['ticket', 'hỗ trợ', 'support'])) {
    return Icons.support_agent_rounded;
  }
  return Icons.smart_toy_outlined;
}

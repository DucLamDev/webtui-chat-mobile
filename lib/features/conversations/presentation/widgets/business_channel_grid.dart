import 'package:flutter/material.dart';

import '../../../../design_system/icons/webtui_icons.dart';
import '../../domain/entities/business_channel_catalog.dart';
import '../../domain/entities/conversation_summary.dart';

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

/// Biểu tượng Lucide của một kênh trong danh sách hội thoại: nhận theo mã kênh
/// (`slug`) trước, rồi theo tên (chung, bảng tin, đơn hàng, ticket, trò chuyện,
/// kế toán); kênh riêng tư là ổ khoá; còn lại là dấu #.
IconData conversationChannelIcon(ConversationSummary channel) {
  if (channel.noticeBot) return WebTuiIcons.bell;
  final bySlug = switch ((channel.slug ?? '').trim().toLowerCase()) {
    'general' || 'chung' => WebTuiIcons.channel,
    'announcements' || 'bang-tin' || 'thong-bao' => WebTuiIcons.announcement,
    'orders' || 'order' || 'don-hang' => WebTuiIcons.orders,
    'ticket' || 'tickets' => WebTuiIcons.ticket,
    'chitchat' || 'tro-chuyen' || 'random' => WebTuiIcons.chitchat,
    'ke-toan' || 'billing' || 'accounting' => WebTuiIcons.accounting,
    _ => null,
  };
  if (bySlug != null) return bySlug;
  final text = channel.title.toLowerCase();
  bool has(List<String> words) => words.any(text.contains);
  if (has(['bảng tin', 'thông báo', 'announcement'])) {
    return WebTuiIcons.announcement;
  }
  if (has(['đơn hàng', 'order'])) return WebTuiIcons.orders;
  if (has(['ticket'])) return WebTuiIcons.ticket;
  if (has(['trò chuyện', 'chitchat', 'random'])) return WebTuiIcons.chitchat;
  if (has(['kế toán', 'accounting'])) return WebTuiIcons.accounting;
  if (channel.isAutomation) return businessChannelIcon(channel);
  if (channel.channelVisibility == ChannelVisibility.private) {
    return WebTuiIcons.channelPrivate;
  }
  return WebTuiIcons.channel;
}

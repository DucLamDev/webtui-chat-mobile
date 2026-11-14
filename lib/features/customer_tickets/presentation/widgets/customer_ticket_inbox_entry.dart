import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../design_system/components/webtui_components.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../controllers/customer_ticket_access_provider.dart';

/// Ô "Ticket khách" đầu tab Nghiệp vụ của hộp thư, kèm số ticket chưa trả lời.
/// Chỉ hiện trên máy chủ nội bộ khi có quyền `order.view`.
class CustomerTicketInboxEntry extends ConsumerWidget {
  const CustomerTicketInboxEntry({required this.workspaceId, super.key});

  final String workspaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(customerTicketAccessProvider);
    final normalizedWorkspaceId = workspaceId.trim();
    if (!access.canView || normalizedWorkspaceId.isEmpty) {
      return const SizedBox.shrink();
    }
    final countProvider = customerTicketUnansweredCountProvider(
      normalizedWorkspaceId,
    );
    final count = ref.watch(countProvider);
    final value = count.valueOrNull;
    final subtitle = switch (value) {
      null when count.isLoading => 'Đang tải số ticket...',
      null => 'Xem và trả lời ticket khách gửi',
      0 => 'Không có ticket chờ trả lời',
      final pending => '$pending ticket chưa trả lời',
    };
    final pending = value ?? 0;
    return Semantics(
      button: true,
      excludeSemantics: true,
      label: 'Ticket khách, $subtitle',
      child: WebTuiConversationListItem(
        key: const Key('customer_ticket_entry'),
        title: 'Ticket khách',
        preview: subtitle,
        timeLabel: '',
        avatarLabel: 'Ticket khách',
        avatarIcon: Icons.confirmation_number_outlined,
        unreadCount: pending,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (pending > 0) ...[
              WebTuiUnreadBadge(count: pending),
              const SizedBox(width: WebTuiSpacing.xs),
            ],
            const Icon(
              CupertinoIcons.chevron_right,
              size: 18,
              color: WebTuiColors.textMuted,
            ),
          ],
        ),
        onTap: () async {
          await context.push<void>(
            Uri(
              path: '/customer-tickets',
              queryParameters: {'workspaceId': normalizedWorkspaceId},
            ).toString(),
          );
          if (context.mounted) ref.invalidate(countProvider);
        },
      ),
    );
  }
}

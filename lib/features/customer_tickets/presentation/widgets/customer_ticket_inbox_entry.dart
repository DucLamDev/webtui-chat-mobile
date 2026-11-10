import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../design_system/components/webtui_components.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_density.dart';
import '../../../../design_system/tokens/webtui_radii.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        WebTuiSpacing.lg,
        WebTuiSpacing.sm,
        WebTuiSpacing.lg,
        0,
      ),
      child: Semantics(
        button: true,
        excludeSemantics: true,
        label: 'Ticket khách, $subtitle',
        child: Material(
          color: WebTuiColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(WebTuiRadii.md),
            side: const BorderSide(color: WebTuiColors.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: const Key('customer_ticket_entry'),
            onTap: () async {
              await context.push<void>(
                Uri(
                  path: '/customer-tickets',
                  queryParameters: {'workspaceId': normalizedWorkspaceId},
                ).toString(),
              );
              if (context.mounted) ref.invalidate(countProvider);
            },
            child: SizedBox(
              height: WebTuiListDensity.conversationItemHeight,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: WebTuiSpacing.md,
                ),
                child: Row(
                  children: [
                    WebTuiAvatar(
                      label: 'Ticket khách',
                      icon: Icons.confirmation_number_outlined,
                      color: WebTuiColors.primary.withValues(alpha: 0.13),
                      foregroundColor: WebTuiColors.primary,
                    ),
                    const SizedBox(width: WebTuiSpacing.md),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Ticket khách',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: WebTuiTypography.bodyMedium.copyWith(
                              color: WebTuiColors.textPrimary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: WebTuiSpacing.xxs),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: WebTuiTypography.bodySmall.copyWith(
                              color: pending > 0
                                  ? WebTuiColors.textSecondary
                                  : WebTuiColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (pending > 0) ...[
                      const SizedBox(width: WebTuiSpacing.sm),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: WebTuiColors.danger,
                          borderRadius: BorderRadius.circular(WebTuiRadii.lg),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: WebTuiSpacing.sm,
                            vertical: WebTuiSpacing.xxs,
                          ),
                          child: Text(
                            pending > 99 ? '99+' : '$pending',
                            style: WebTuiTypography.labelSmall.copyWith(
                              color: WebTuiColors.textOnPrimary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(width: WebTuiSpacing.xs),
                    const Icon(
                      CupertinoIcons.chevron_right,
                      size: 18,
                      color: WebTuiColors.textMuted,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

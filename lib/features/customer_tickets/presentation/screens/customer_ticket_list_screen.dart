import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../design_system/components/webtui_components.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../../../workspace/presentation/controllers/workspace_controller.dart';
import '../../application/customer_ticket_channel_route.dart';
import '../../domain/entities/customer_ticket.dart';
import '../controllers/customer_ticket_access_provider.dart';
import '../controllers/customer_ticket_list_controller.dart';
import '../widgets/customer_ticket_formatters.dart';
import '../widgets/customer_ticket_states.dart';

/// Hộp thư ticket khách (máy chủ nội bộ): lọc, tìm, cuộn tải thêm.
class CustomerTicketListScreen extends ConsumerWidget {
  const CustomerTicketListScreen({
    this.workspaceId,
    this.channelId,
    this.channelTitle,
    super.key,
  });

  final String? workspaceId;

  /// Kênh bot "Ticket" đã bấm để vào đây (nếu có): hiện nút mở kênh chat đó
  /// để vẫn dùng được lệnh bot.
  final String? channelId;
  final String? channelTitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(customerTicketAccessProvider);
    final gate = customerTicketAccessGate(access);
    final resolvedWorkspaceId = gate != null
        ? ''
        : _workspaceIdOrActive(ref, workspaceId);
    return Scaffold(
      backgroundColor: WebTuiColors.background,
      appBar: AppBar(
        title: const Text('Ticket khách'),
        surfaceTintColor: Colors.transparent,
        actions: [
          if (_channelChatLocation(resolvedWorkspaceId) case final location?)
            IconButton(
              key: const ValueKey('customer-ticket-open-channel'),
              tooltip: 'Mở kênh chat Ticket',
              icon: const Icon(Icons.forum_outlined),
              onPressed: () => context.push<void>(location),
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child:
            gate ??
            (resolvedWorkspaceId.isEmpty
                ? const WebTuiEmptyState(
                    title: 'Chưa chọn workspace',
                    message: 'Chọn workspace trước khi xem ticket khách.',
                    icon: Icons.confirmation_number_outlined,
                  )
                : _CustomerTicketListBody(workspaceId: resolvedWorkspaceId)),
      ),
    );
  }
}

extension on CustomerTicketListScreen {
  String? _channelChatLocation(String resolvedWorkspaceId) =>
      customerTicketChannelChatLocation(
        channelId: channelId,
        channelTitle: channelTitle,
        workspaceId: resolvedWorkspaceId.isEmpty
            ? workspaceId
            : resolvedWorkspaceId,
      );
}

String _workspaceIdOrActive(WidgetRef ref, String? workspaceId) {
  final requested = workspaceId?.trim() ?? '';
  if (requested.isNotEmpty) return requested;
  return ref
          .watch(
            workspaceControllerProvider.select(
              (state) => state.activeWorkspace?.id,
            ),
          )
          ?.trim() ??
      '';
}

const _filters = [
  CustomerTicketFilter.unanswered,
  CustomerTicketFilter.answered,
  CustomerTicketFilter.all,
];

class _CustomerTicketListBody extends ConsumerWidget {
  const _CustomerTicketListBody({required this.workspaceId});

  final String workspaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = customerTicketListControllerProvider(workspaceId);
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    final now = ref.watch(customerTicketClockProvider)();
    final unanswered = state.counts.unanswered;
    final tabs = [
      unanswered > 0 ? 'Chưa trả lời $unanswered' : 'Chưa trả lời',
      'Đã trả lời',
      'Tất cả',
    ];
    final selectedIndex = _filters.indexOf(state.filter);

    return RefreshIndicator(
      onRefresh: controller.refresh,
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if ((notification is ScrollUpdateNotification ||
                  notification is OverscrollNotification) &&
              notification.metrics.extentAfter < 480) {
            unawaited(controller.loadMore());
          }
          return false;
        },
        child: CustomScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  WebTuiSpacing.lg,
                  WebTuiSpacing.md,
                  WebTuiSpacing.lg,
                  WebTuiSpacing.sm,
                ),
                child: WebTuiSearchBar(
                  hintText: 'Tìm mã ticket, tên, email khách...',
                  debounceDuration: const Duration(milliseconds: 350),
                  onChanged: (value) => unawaited(controller.setSearch(value)),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: WebTuiSpacing.lg,
                ),
                child: WebTuiSegmentedTabs(
                  tabs: tabs,
                  selectedIndex: selectedIndex < 0 ? 0 : selectedIndex,
                  onChanged: (index) =>
                      unawaited(controller.setFilter(_filters[index])),
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: WebTuiSpacing.sm)),
            ..._content(context, state, controller, now),
            const SliverToBoxAdapter(child: SizedBox(height: WebTuiSpacing.xl)),
          ],
        ),
      ),
    );
  }

  List<Widget> _content(
    BuildContext context,
    CustomerTicketListState state,
    CustomerTicketListController controller,
    DateTime now,
  ) {
    if (state.forbidden) {
      return [
        SliverToBoxAdapter(
          child: CustomerTicketNoAccessState(message: state.errorMessage),
        ),
      ];
    }
    if (state.isLoading && state.items.isEmpty) {
      return const [
        SliverToBoxAdapter(
          child: WebTuiLoadingState(message: 'Đang tải ticket...'),
        ),
      ];
    }
    final error = state.errorMessage;
    if (error != null && state.items.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: WebTuiErrorState(
            title: 'Không tải được ticket',
            message: error,
            onRetry: () => unawaited(controller.load()),
          ),
        ),
      ];
    }
    if (state.items.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: WebTuiEmptyState(
            title: state.search.isNotEmpty
                ? 'Không tìm thấy ticket'
                : switch (state.filter) {
                    CustomerTicketFilter.unanswered => 'Đã trả lời hết',
                    CustomerTicketFilter.answered =>
                      'Chưa có ticket đã trả lời',
                    CustomerTicketFilter.all => 'Chưa có ticket',
                  },
            message: state.search.isNotEmpty
                ? 'Thử tìm bằng mã ticket, tên hoặc email khác.'
                : 'Ticket khách gửi trên hệ thống order sẽ hiện ở đây.',
            icon: Icons.confirmation_number_outlined,
          ),
        ),
      ];
    }
    return [
      WebTuiSliverListSurface(
        itemCount: state.items.length,
        itemBuilder: (context, index) {
          final ticket = state.items[index];
          return CustomerTicketTile(
            ticket: ticket,
            now: now,
            currentUserId: state.currentUserId,
            onTap: () => _openTicket(context, controller, ticket),
          );
        },
      ),
      if (state.isLoadingMore)
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(WebTuiSpacing.lg),
            child: Center(
              child: SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
        )
      else if (state.loadMoreErrorMessage != null || state.hasMore)
        SliverToBoxAdapter(
          child: Center(
            child: TextButton.icon(
              onPressed: () => unawaited(controller.retryLoadMore()),
              icon: const Icon(Icons.expand_more_rounded),
              label: Text(
                state.loadMoreErrorMessage != null
                    ? 'Tải thêm lỗi, thử lại'
                    : 'Tải thêm',
              ),
            ),
          ),
        ),
    ];
  }

  Future<void> _openTicket(
    BuildContext context,
    CustomerTicketListController controller,
    CustomerTicketSummary ticket,
  ) async {
    await context.push<void>(
      Uri(
        path: '/customer-tickets/${Uri.encodeComponent(ticket.ticketId)}',
        queryParameters: {'workspaceId': workspaceId},
      ).toString(),
    );
    if (controller.mounted) unawaited(controller.refresh());
  }
}

/// Một dòng ticket: `#id · khách`, giờ, xem trước, nhãn dịch vụ / thời gian
/// chờ / tin mới / người xử lý / nháp AI.
class CustomerTicketTile extends StatelessWidget {
  const CustomerTicketTile({
    required this.ticket,
    required this.now,
    required this.onTap,
    this.currentUserId,
    super.key,
  });

  final CustomerTicketSummary ticket;
  final DateTime now;
  final String? currentUserId;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final waiting = customerTicketWaitingMinutes(ticket, now);
    final tone = customerTicketWaitingTone(waiting);
    final assignee = ticket.assignee;
    final staffPrefix = ticket.lastSender == CustomerTicketSender.staff
        ? '${ticket.lastStaffName.isEmpty ? 'Nhân viên' : ticket.lastStaffName}: '
        : '';
    final preview = ticket.preview.isEmpty
        ? '(không có nội dung)'
        : ticket.preview;
    return Material(
      color: WebTuiColors.surface,
      child: InkWell(
        key: ValueKey('customer_ticket_${ticket.ticketId}'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            WebTuiSpacing.lg,
            WebTuiSpacing.md,
            WebTuiSpacing.lg,
            WebTuiSpacing.md,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              WebTuiAvatar(label: ticket.customerLabel, size: 42),
              const SizedBox(width: WebTuiSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '#${ticket.ticketId} · ${ticket.customerLabel}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: WebTuiTypography.bodyMedium.copyWith(
                              color: WebTuiColors.textPrimary,
                              fontWeight: ticket.isUnanswered
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: WebTuiSpacing.sm),
                        Text(
                          customerTicketListTime(
                            ticket.lastMessageAt ?? ticket.createdAt,
                            now,
                          ),
                          style: WebTuiTypography.labelSmall.copyWith(
                            color: WebTuiColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: WebTuiSpacing.xs),
                    Text.rich(
                      TextSpan(
                        children: [
                          if (staffPrefix.isNotEmpty)
                            TextSpan(
                              text: staffPrefix,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: WebTuiColors.textSecondary,
                              ),
                            ),
                          TextSpan(text: preview),
                        ],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: WebTuiTypography.bodySmall.copyWith(
                        color: WebTuiColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: WebTuiSpacing.sm),
                    Wrap(
                      spacing: WebTuiSpacing.xs,
                      runSpacing: WebTuiSpacing.xs,
                      children: [
                        if (ticket.service.isNotEmpty)
                          WebTuiStatusPill(
                            label: ticket.service,
                            color: WebTuiColors.textSecondary,
                          ),
                        if (waiting != null)
                          WebTuiStatusPill(
                            label: customerTicketWaitingLabel(waiting),
                            color: switch (tone) {
                              CustomerTicketWaitingTone.late =>
                                WebTuiColors.danger,
                              CustomerTicketWaitingTone.warning =>
                                WebTuiColors.accentAmber,
                              CustomerTicketWaitingTone.normal =>
                                WebTuiColors.primary,
                            },
                          )
                        else if (ticket.status == CustomerTicketStatus.answered)
                          const WebTuiStatusPill(
                            label: 'Đã trả lời',
                            color: WebTuiColors.accentGreen,
                          ),
                        if (ticket.isUnanswered && ticket.newMessageCount > 0)
                          WebTuiStatusPill(
                            label: '${ticket.newMessageCount} tin mới',
                            color: WebTuiColors.danger,
                          ),
                        if (assignee != null)
                          assignee.isUser(currentUserId)
                              ? const WebTuiStatusPill(
                                  label: 'Bạn đang xử lý',
                                  color: WebTuiColors.accentGreen,
                                )
                              : WebTuiStatusPill(
                                  label:
                                      '${assignee.name.isEmpty ? 'Người khác' : assignee.name} đang xử lý',
                                  color: WebTuiColors.textSecondary,
                                ),
                        if (ticket.hasAiDraft)
                          const WebTuiStatusPill(
                            label: 'Có nháp AI',
                            color: WebTuiColors.primary,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

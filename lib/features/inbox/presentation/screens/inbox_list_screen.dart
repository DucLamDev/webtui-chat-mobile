import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../design_system/components/webtui_components.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_radii.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../../../workspace/presentation/controllers/workspace_controller.dart';
import '../../application/inbox_access_policy.dart';
import '../../domain/entities/inbox.dart';
import '../controllers/inbox_access_provider.dart';
import '../controllers/inbox_list_controller.dart';
import '../widgets/inbox_formatters.dart';

/// Màn "Hộp thư khách": danh sách hội thoại có lọc.
class InboxListScreen extends ConsumerWidget {
  const InboxListScreen({this.workspaceId, super.key});

  final String? workspaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(inboxAccessProvider(workspaceId));
    final gate = inboxAccessGate(access);
    final requested = workspaceId?.trim() ?? '';
    final active = ref.watch(
      workspaceControllerProvider.select((state) => state.activeWorkspace?.id),
    );
    final id = gate != null
        ? ''
        : (requested.isNotEmpty ? requested : active ?? '');
    return Scaffold(
      backgroundColor: WebTuiColors.background,
      appBar: AppBar(
        title: const Text('Hộp thư khách'),
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        top: false,
        child:
            gate ??
            (id.isEmpty
                ? const WebTuiEmptyState(
                    title: 'Chưa chọn workspace',
                    message: 'Chọn workspace trước khi xem hộp thư khách.',
                    icon: Icons.forum_outlined,
                  )
                : _InboxListBody(workspaceId: id)),
      ),
    );
  }
}

/// Chặn trước khi tải: máy chủ không hỗ trợ / đang tải quyền / thiếu quyền.
Widget? inboxAccessGate(InboxAccess access) {
  if (!access.serverSupported) {
    return const InboxNoAccessState(
      message: 'Máy chủ này chưa có hộp thư khách.',
    );
  }
  if (access.isPending) {
    return const WebTuiLoadingState(message: 'Đang kiểm tra quyền...');
  }
  if (!access.canView) return const InboxNoAccessState();
  return null;
}

class InboxNoAccessState extends StatelessWidget {
  const InboxNoAccessState({this.message, super.key});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return WebTuiEmptyState(
      key: const Key('inbox_no_access'),
      title: 'Không có quyền xem hộp thư khách',
      message:
          message ?? 'Bạn cần quyền xem hộp thư khách trong workspace này.',
      icon: Icons.lock_outline_rounded,
    );
  }
}

class _InboxListBody extends ConsumerWidget {
  const _InboxListBody({required this.workspaceId});

  final String workspaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = inboxListControllerProvider(workspaceId);
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    return Column(
      children: [
        SingleChildScrollView(
          key: const Key('inbox_filter_status'),
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(
            WebTuiSpacing.md,
            WebTuiSpacing.md,
            WebTuiSpacing.md,
            0,
          ),
          child: Row(
            children: [
              for (final filter in InboxStatusFilter.values)
                Padding(
                  padding: const EdgeInsets.only(right: WebTuiSpacing.sm),
                  child: ChoiceChip(
                    key: Key('inbox_status_${filter.name}'),
                    label: Text(filter.label),
                    selected: state.status == filter,
                    onSelected: (_) => controller.setFilters(status: filter),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(WebTuiSpacing.md),
          child: SegmentedButton<InboxAssigneeFilter>(
            key: const Key('inbox_filter_assignee'),
            segments: [
              for (final filter in InboxAssigneeFilter.values)
                ButtonSegment(value: filter, label: Text(filter.label)),
            ],
            selected: {state.assignee},
            onSelectionChanged: (value) =>
                controller.setFilters(assignee: value.first),
          ),
        ),
        Expanded(child: _content(context, state, controller)),
      ],
    );
  }

  Widget _content(
    BuildContext context,
    InboxListState state,
    InboxListController controller,
  ) {
    if (state.forbidden) return const InboxNoAccessState();
    if (!state.hasLoaded && state.isLoading) {
      return const WebTuiLoadingState(message: 'Đang tải hộp thư khách...');
    }
    if (state.errorMessage != null && state.items.isEmpty) {
      return WebTuiErrorState(
        title: 'Không tải được hộp thư khách',
        message: state.errorMessage!,
        onRetry: controller.load,
      );
    }
    if (state.items.isEmpty) {
      return RefreshIndicator(
        onRefresh: controller.load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            WebTuiEmptyState(
              key: Key('inbox_empty'),
              title: 'Chưa có hội thoại nào',
              message: 'Tin khách mới sẽ hiện ở đây.',
              icon: Icons.forum_outlined,
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: controller.load,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          WebTuiSpacing.md,
          0,
          WebTuiSpacing.md,
          WebTuiSpacing.md,
        ),
        itemCount: state.items.length + (state.hasMore ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(height: WebTuiSpacing.sm),
        itemBuilder: (context, index) {
          if (index >= state.items.length) {
            return Center(
              child: TextButton(
                key: const Key('inbox_load_more'),
                onPressed: state.isLoadingMore ? null : controller.loadMore,
                child: Text(state.isLoadingMore ? 'Đang tải...' : 'Tải thêm'),
              ),
            );
          }
          final item = state.items[index];
          return InboxConversationTile(
            conversation: item,
            onTap: () => context.push(
              inboxConversationLocation(
                conversationId: item.id,
                workspaceId: workspaceId,
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Một dòng hội thoại: nhãn, nội dung gần nhất, giờ, số chưa đọc, chip nguồn.
class InboxConversationTile extends StatelessWidget {
  const InboxConversationTile({
    required this.conversation,
    required this.onTap,
    super.key,
  });

  final InboxConversation conversation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final item = conversation;
    final unread = item.unreadCount;
    final extra = [
      if (item.assigneeName.isNotEmpty) 'Do ${item.assigneeName} xử lý',
      for (final tag in item.tags) '#${tag.name}',
    ].join('  ·  ');
    return Material(
      key: Key('inbox_item_${item.id}'),
      color: WebTuiColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(WebTuiRadii.md),
        side: const BorderSide(color: WebTuiColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: onTap,
        leading: Chip(
          key: Key('inbox_source_${item.id}'),
          label: Text(item.source.chipLabel),
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
        ),
        title: Text(
          item.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: unread > 0 ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.lastMessagePreview.isEmpty
                  ? 'Chưa có tin nhắn'
                  : item.lastMessagePreview,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (extra.isNotEmpty)
              Text(
                extra,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                key: Key('inbox_extra_${item.id}'),
                style: const TextStyle(
                  fontSize: 12,
                  color: WebTuiColors.textSecondary,
                ),
              ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              formatInboxTime(item.lastMessageAt),
              style: const TextStyle(
                fontSize: 12,
                color: WebTuiColors.textMuted,
              ),
            ),
            if (unread > 0) ...[
              const SizedBox(height: WebTuiSpacing.xs),
              Container(
                key: Key('inbox_unread_${item.id}'),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: WebTuiColors.primary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  unread > 99 ? '99+' : '$unread',
                  style: const TextStyle(
                    color: WebTuiColors.textOnPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Đường dẫn màn hội thoại, luôn kèm workspace để không mở nhầm workspace.
String inboxConversationLocation({
  required String conversationId,
  required String workspaceId,
}) {
  return Uri(
    path: '/inbox/${Uri.encodeComponent(conversationId.trim())}',
    queryParameters: <String, String>{'workspaceId': workspaceId.trim()},
  ).toString();
}

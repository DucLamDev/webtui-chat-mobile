import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../design_system/components/webtui_components.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../../../workspace/presentation/controllers/workspace_controller.dart';
import '../../application/approval_access_policy.dart';
import '../../domain/entities/approval.dart';
import '../controllers/approval_access_provider.dart';
import '../controllers/approval_list_controller.dart';
import '../widgets/approval_formatters.dart';

/// Phê duyệt: tab Đang chờ / Đã xử lý.
class ApprovalListScreen extends ConsumerWidget {
  const ApprovalListScreen({this.workspaceId, super.key});

  final String? workspaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(approvalAccessProvider(workspaceId));
    final gate = approvalAccessGate(access);
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
        title: const Text('Phê duyệt'),
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        top: false,
        child:
            gate ??
            (id.isEmpty
                ? const WebTuiEmptyState(
                    title: 'Chưa chọn workspace',
                    message: 'Chọn workspace trước khi xem phê duyệt.',
                    icon: Icons.fact_check_outlined,
                  )
                : _ApprovalListBody(workspaceId: id)),
      ),
    );
  }
}

/// Chặn trước khi tải: máy chủ không hỗ trợ / đang tải quyền / thiếu quyền.
Widget? approvalAccessGate(ApprovalAccess access) {
  if (!access.serverSupported) {
    return const ApprovalNoAccessState(
      message: 'Máy chủ này chưa có tính năng phê duyệt.',
    );
  }
  if (access.isPending) {
    return const WebTuiLoadingState(message: 'Đang kiểm tra quyền...');
  }
  if (!access.canView) return const ApprovalNoAccessState();
  return null;
}

class ApprovalNoAccessState extends StatelessWidget {
  const ApprovalNoAccessState({this.message, super.key});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return WebTuiEmptyState(
      key: const Key('approval_no_access'),
      title: 'Không có quyền xem phê duyệt',
      message: message ?? 'Bạn cần quyền xem phê duyệt trong workspace này.',
      icon: Icons.lock_outline_rounded,
    );
  }
}

class _ApprovalListBody extends ConsumerStatefulWidget {
  const _ApprovalListBody({required this.workspaceId});

  final String workspaceId;

  @override
  ConsumerState<_ApprovalListBody> createState() => _ApprovalListBodyState();
}

class _ApprovalListBodyState extends ConsumerState<_ApprovalListBody>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref
          .read(approvalListControllerProvider(widget.workspaceId).notifier)
          .refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = approvalListControllerProvider(widget.workspaceId);
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(WebTuiSpacing.md),
          child: SegmentedButton<ApprovalFilter>(
            key: const Key('approval_filter'),
            segments: [
              for (final filter in ApprovalFilter.values)
                ButtonSegment(value: filter, label: Text(filter.label)),
            ],
            selected: {state.filter},
            onSelectionChanged: (value) => controller.setFilter(value.first),
          ),
        ),
        Expanded(child: _content(context, state, controller)),
      ],
    );
  }

  Widget _content(
    BuildContext context,
    ApprovalListState state,
    ApprovalListController controller,
  ) {
    if (state.forbidden) return const ApprovalNoAccessState();
    if (!state.hasLoaded && state.isLoading) {
      return const WebTuiLoadingState(message: 'Đang tải phê duyệt...');
    }
    if (state.errorMessage != null && state.items.isEmpty) {
      return WebTuiErrorState(
        title: 'Không tải được phê duyệt',
        message: state.errorMessage!,
        onRetry: controller.load,
      );
    }
    if (state.items.isEmpty) {
      return WebTuiEmptyState(
        key: const Key('approval_empty'),
        title: state.filter == ApprovalFilter.pending
            ? 'Không có yêu cầu đang chờ'
            : 'Chưa có yêu cầu nào đã xử lý',
        message: 'Yêu cầu phê duyệt mới sẽ hiện ở đây.',
        icon: Icons.fact_check_outlined,
      );
    }
    return RefreshIndicator(
      onRefresh: controller.load,
      child: ListView.separated(
        padding: const EdgeInsets.all(WebTuiSpacing.md),
        itemCount: state.items.length + (state.hasMore ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(height: WebTuiSpacing.sm),
        itemBuilder: (context, index) {
          if (index >= state.items.length) {
            return Center(
              child: TextButton(
                onPressed: state.isLoadingMore ? null : controller.loadMore,
                child: Text(state.isLoadingMore ? 'Đang tải...' : 'Tải thêm'),
              ),
            );
          }
          final item = state.items[index];
          return Card(
            key: Key('approval_item_${item.id}'),
            child: ListTile(
              title: Text(
                item.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                '${item.sourceLabel} · ${item.status.label} · '
                '${item.approvalsCount}/${item.requiredApprovals} phiếu'
                '${item.expiresAt == null ? '' : ' · hạn ${formatApprovalTime(item.expiresAt!)}'}',
              ),
              trailing: item.canDecide && item.isPending
                  ? const Icon(Icons.how_to_vote_outlined)
                  : const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push(
                approvalDetailLocation(
                  approvalId: item.id,
                  workspaceId: widget.workspaceId,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Đường dẫn màn chi tiết, luôn kèm workspace của danh sách để không mở nhầm
/// workspace đang chọn.
String approvalDetailLocation({
  required String approvalId,
  required String workspaceId,
}) {
  return Uri(
    path: '/approvals/${Uri.encodeComponent(approvalId.trim())}',
    queryParameters: <String, String>{'workspaceId': workspaceId.trim()},
  ).toString();
}

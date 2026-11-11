import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../design_system/components/webtui_components.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../../../workspace/presentation/controllers/workspace_controller.dart';
import '../../domain/entities/approval.dart';
import '../controllers/approval_access_provider.dart';
import '../controllers/approval_detail_controller.dart';
import '../controllers/approval_list_controller.dart';
import '../widgets/approval_formatters.dart';
import 'approval_list_screen.dart';

/// Chi tiết một yêu cầu phê duyệt, kèm nút Duyệt / Từ chối khi `can_decide`.
class ApprovalDetailScreen extends ConsumerWidget {
  const ApprovalDetailScreen({
    required this.approvalId,
    this.workspaceId,
    super.key,
  });

  final String approvalId;
  final String? workspaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gate = approvalAccessGate(
      ref.watch(approvalAccessProvider(workspaceId)),
    );
    final requested = workspaceId?.trim() ?? '';
    final active = ref.watch(
      workspaceControllerProvider.select((state) => state.activeWorkspace?.id),
    );
    final id = requested.isNotEmpty ? requested : active ?? '';
    return Scaffold(
      backgroundColor: WebTuiColors.background,
      appBar: AppBar(
        title: const Text('Chi tiết phê duyệt'),
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
                : _Body(workspaceId: id, approvalId: approvalId)),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.workspaceId, required this.approvalId});

  final String workspaceId;
  final String approvalId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (workspaceId: workspaceId, approvalId: approvalId);
    final provider = approvalDetailControllerProvider(key);
    ref.listen(provider.select((state) => state.actionMessage), (_, message) {
      if (message == null) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    });
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    final approval = state.approval;
    if (state.forbidden) return const ApprovalNoAccessState();
    if (approval == null) {
      if (state.isLoading) {
        return const WebTuiLoadingState(message: 'Đang tải yêu cầu...');
      }
      return WebTuiErrorState(
        title: 'Không tải được yêu cầu',
        message: state.errorMessage ?? 'Hãy thử lại.',
        onRetry: controller.load,
      );
    }
    return ApprovalDetailView(
      approval: approval,
      isSubmitting: state.isSubmitting,
      onDecide: (decision, comment) async {
        final ok = await controller.decide(decision, comment: comment);
        if (ok) {
          // Danh sách đang mở (nếu có) phải thấy trạng thái mới.
          ref.invalidate(approvalListControllerProvider);
        }
      },
    );
  }
}

/// Phần hiển thị thuần (dễ test): không đọc provider.
class ApprovalDetailView extends StatefulWidget {
  const ApprovalDetailView({
    required this.approval,
    required this.onDecide,
    this.isSubmitting = false,
    super.key,
  });

  final ApprovalRequest approval;
  final bool isSubmitting;
  final Future<void> Function(ApprovalDecisionKind decision, String comment)
  onDecide;

  @override
  State<ApprovalDetailView> createState() => _ApprovalDetailViewState();
}

class _ApprovalDetailViewState extends State<ApprovalDetailView> {
  final _comment = TextEditingController();

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final approval = widget.approval;
    final preview = approvalPayloadPreview(approval.payload);
    final canDecide = approval.canDecide && approval.isPending;
    return ListView(
      padding: const EdgeInsets.all(WebTuiSpacing.md),
      children: [
        Text(approval.title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: WebTuiSpacing.sm),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(width: 96, child: Text('Trạng thái')),
              Expanded(child: ApprovalStatusText(approval: approval)),
            ],
          ),
        ),
        _row('Nguồn', approval.sourceLabel),
        _row('Hành động', approval.action),
        if (approval.requestedBy != null)
          _row('Người tạo', approval.requestedBy!),
        _row(
          'Số phiếu',
          '${approval.approvalsCount}/${approval.requiredApprovals}',
        ),
        if (approval.createdAt != null)
          _row('Tạo lúc', formatApprovalTime(approval.createdAt!)),
        if (approval.expiresAt != null)
          _row('Hạn duyệt', formatApprovalTime(approval.expiresAt!)),
        if (preview.isNotEmpty) ...[
          const SizedBox(height: WebTuiSpacing.sm),
          Text('Nội dung', style: Theme.of(context).textTheme.titleSmall),
          SelectableText(preview),
        ],
        if (approval.decisions.isNotEmpty) ...[
          const SizedBox(height: WebTuiSpacing.md),
          Text('Phiếu đã bỏ', style: Theme.of(context).textTheme.titleSmall),
          for (final vote in approval.decisions)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(
                vote.decision == ApprovalDecisionKind.approve
                    ? 'Đồng ý'
                    : 'Từ chối',
              ),
              subtitle: Text(
                [
                  vote.userId,
                  if (vote.comment.isNotEmpty) vote.comment,
                ].join(' · '),
              ),
            ),
        ],
        if (canDecide) ...[
          const SizedBox(height: WebTuiSpacing.md),
          TextField(
            key: const Key('approval_comment'),
            controller: _comment,
            maxLength: 500,
            decoration: const InputDecoration(
              labelText: 'Ghi chú (không bắt buộc)',
            ),
          ),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const Key('approval_reject'),
                  onPressed: widget.isSubmitting
                      ? null
                      : () => widget.onDecide(
                          ApprovalDecisionKind.reject,
                          _comment.text,
                        ),
                  child: const Text('Từ chối'),
                ),
              ),
              const SizedBox(width: WebTuiSpacing.sm),
              Expanded(
                child: FilledButton(
                  key: const Key('approval_approve'),
                  onPressed: widget.isSubmitting
                      ? null
                      : () => widget.onDecide(
                          ApprovalDecisionKind.approve,
                          _comment.text,
                        ),
                  child: const Text('Duyệt'),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 96, child: Text(label)),
          Expanded(child: Text(value.isEmpty ? '-' : value)),
        ],
      ),
    );
  }
}

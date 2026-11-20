import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webtui_chat/l10n/app_strings.dart';

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
        title: Text(tr('Chi tiết phê duyệt', 'Approval details')),
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        top: false,
        child:
            gate ??
            (id.isEmpty
                ? WebTuiEmptyState(
                    title: tr('Chưa chọn workspace', 'No workspace selected'),
                    message: tr(
                      'Chọn workspace trước khi xem phê duyệt.',
                      'Select a workspace before viewing approvals.',
                    ),
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
        return WebTuiLoadingState(
          message: tr('Đang tải yêu cầu...', 'Loading request...'),
        );
      }
      return WebTuiErrorState(
        title: tr('Không tải được yêu cầu', 'Couldn\'t load the request'),
        message: state.errorMessage ?? tr('Hãy thử lại.', 'Try again.'),
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
  ApprovalDecisionKind? _sending;

  bool get _busy => widget.isSubmitting || _sending != null;

  Widget _label(ApprovalDecisionKind kind, String text) {
    if (!_busy || (_sending != null && _sending != kind)) return Text(text);
    return const SizedBox(
      width: 18,
      height: 18,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
  }

  Future<void> _send(ApprovalDecisionKind kind, String comment) async {
    if (_busy) return;
    setState(() => _sending = kind);
    try {
      await widget.onDecide(kind, comment);
    } finally {
      if (mounted) setState(() => _sending = null);
    }
  }

  Future<void> _approve() async {
    final ok = await showWebTuiConfirmDialog(
      context,
      title: tr('Duyệt yêu cầu?', 'Approve this request?'),
      message: widget.approval.title,
      confirmLabel: tr('Duyệt', 'Approve'),
    );
    if (ok && mounted) await _send(ApprovalDecisionKind.approve, _comment.text);
  }

  Future<void> _reject() async {
    final reason = await showWebTuiTextInputDialog(
      context,
      title: tr('Từ chối yêu cầu?', 'Reject this request?'),
      message: widget.approval.title,
      label: tr('Lý do từ chối', 'Reason for rejecting'),
      initialValue: _comment.text,
      confirmLabel: tr('Từ chối', 'Reject'),
      maxLength: 500,
      validator: (value) => value.trim().isEmpty
          ? tr('Hãy nhập lý do.', 'Please enter a reason.')
          : null,
    );
    if (reason == null || reason.trim().isEmpty || !mounted) return;
    _comment.text = reason;
    await _send(ApprovalDecisionKind.reject, reason);
  }

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
              SizedBox(width: 96, child: Text(tr('Trạng thái', 'Status'))),
              Expanded(child: ApprovalStatusText(approval: approval)),
            ],
          ),
        ),
        _row(tr('Nguồn', 'Source'), approval.sourceLabel),
        _row(tr('Hành động', 'Action'), approval.action),
        if (approval.requestedBy != null)
          _row(tr('Người tạo', 'Created by'), approval.requestedBy!),
        _row(
          tr('Số phiếu', 'Votes'),
          '${approval.approvalsCount}/${approval.requiredApprovals}',
        ),
        if (approval.createdAt != null)
          _row(
            tr('Tạo lúc', 'Created at'),
            formatApprovalTime(approval.createdAt!),
          ),
        if (approval.expiresAt != null)
          _row(
            tr('Hạn duyệt', 'Approval deadline'),
            formatApprovalTime(approval.expiresAt!),
          ),
        if (preview.isNotEmpty) ...[
          const SizedBox(height: WebTuiSpacing.sm),
          Text(
            tr('Nội dung', 'Content'),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          SelectableText(preview),
        ],
        if (approval.decisions.isNotEmpty) ...[
          const SizedBox(height: WebTuiSpacing.md),
          Text(
            tr('Phiếu đã bỏ', 'Votes cast'),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          for (final vote in approval.decisions)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(
                vote.decision == ApprovalDecisionKind.approve
                    ? tr('Đồng ý', 'Approve')
                    : tr('Từ chối', 'Reject'),
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
            decoration: InputDecoration(
              labelText: tr('Ghi chú (không bắt buộc)', 'Note (optional)'),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const Key('approval_reject'),
                  onPressed: _busy ? null : _reject,
                  child: _label(
                    ApprovalDecisionKind.reject,
                    tr('Từ chối', 'Reject'),
                  ),
                ),
              ),
              const SizedBox(width: WebTuiSpacing.sm),
              Expanded(
                child: FilledButton(
                  key: const Key('approval_approve'),
                  onPressed: _busy ? null : _approve,
                  child: _label(
                    ApprovalDecisionKind.approve,
                    tr('Duyệt', 'Approve'),
                  ),
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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:webtui_chat/l10n/app_strings.dart';

import '../../../../design_system/components/webtui_components.dart';
import '../../../../design_system/icons/webtui_icons.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_radii.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../../../workspace/presentation/controllers/workspace_controller.dart';
import '../../domain/entities/customer_ticket.dart';
import '../controllers/customer_ticket_access_provider.dart';
import '../controllers/customer_ticket_detail_controller.dart';
import '../widgets/customer_ticket_formatters.dart';
import '../widgets/customer_ticket_media.dart';
import '../widgets/customer_ticket_states.dart';

/// Chi tiết một ticket khách: luồng tin, nháp AI, trả lời (khi có quyền
/// `order.ticket_reply`), nhận xử lý, đánh dấu đã xử lý.
class CustomerTicketDetailScreen extends ConsumerWidget {
  const CustomerTicketDetailScreen({
    required this.ticketId,
    this.workspaceId,
    super.key,
  });

  final String ticketId;
  final String? workspaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(customerTicketAccessProvider);
    final gate = customerTicketAccessGate(access);
    final normalizedTicketId = ticketId.trim();
    if (gate != null) {
      return _DetailFrame(ticketId: normalizedTicketId, body: gate);
    }
    final requested = workspaceId?.trim() ?? '';
    final resolvedWorkspaceId = requested.isNotEmpty
        ? requested
        : ref
                  .watch(
                    workspaceControllerProvider.select(
                      (state) => state.activeWorkspace?.id,
                    ),
                  )
                  ?.trim() ??
              '';
    if (resolvedWorkspaceId.isEmpty) {
      return _DetailFrame(
        ticketId: normalizedTicketId,
        body: WebTuiEmptyState(
          title: tr('Chưa chọn workspace', 'No workspace selected'),
          message: tr(
            'Chọn workspace trước khi xem ticket khách.',
            'Select a workspace before viewing customer tickets.',
          ),
          icon: Icons.confirmation_number_outlined,
        ),
      );
    }
    return _CustomerTicketDetailView(
      args: (workspaceId: resolvedWorkspaceId, ticketId: normalizedTicketId),
      canReply: access.canReply,
    );
  }
}

class _DetailFrame extends StatelessWidget {
  const _DetailFrame({required this.ticketId, required this.body});

  final String ticketId;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WebTuiColors.background,
      appBar: AppBar(
        leading: const _BackButton(),
        title: Text(
          ticketId.isEmpty
              ? tr('Ticket khách', 'Customer tickets')
              : '#$ticketId',
        ),
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(top: false, child: body),
    );
  }
}

/// Mở thẳng bằng đường dẫn (không có trang trước) thì quay về danh sách.
class _BackButton extends StatelessWidget {
  const _BackButton({this.workspaceId});

  final String? workspaceId;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tr('Quay lại', 'Back'),
      icon: const BackButtonIcon(),
      onPressed: () {
        if (context.canPop()) {
          context.pop();
          return;
        }
        final id = workspaceId?.trim() ?? '';
        context.go(
          Uri(
            path: '/customer-tickets',
            queryParameters: id.isEmpty ? null : {'workspaceId': id},
          ).toString(),
        );
      },
    );
  }
}

enum _TicketMenuAction { claim, release, markAnswered, reopen, reload, info }

class _CustomerTicketDetailView extends ConsumerStatefulWidget {
  const _CustomerTicketDetailView({required this.args, required this.canReply});

  final CustomerTicketDetailArgs args;
  final bool canReply;

  @override
  ConsumerState<_CustomerTicketDetailView> createState() =>
      _CustomerTicketDetailViewState();
}

class _CustomerTicketDetailViewState
    extends ConsumerState<_CustomerTicketDetailView> {
  final _composer = TextEditingController();

  CustomerTicketDetailController get _controller =>
      ref.read(customerTicketDetailControllerProvider(widget.args).notifier);

  @override
  void dispose() {
    _composer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final args = widget.args;
    final state = ref.watch(customerTicketDetailControllerProvider(args));
    final now = ref.watch(customerTicketClockProvider)();
    final detail = state.detail;
    final canReply = widget.canReply && !state.forbidden;

    return Scaffold(
      backgroundColor: WebTuiColors.chatBackground,
      appBar: AppBar(
        leading: _BackButton(workspaceId: args.workspaceId),
        titleSpacing: 0,
        surfaceTintColor: Colors.transparent,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '#${args.ticketId}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: WebTuiTypography.titleMedium.copyWith(
                color: WebTuiColors.textPrimary,
              ),
            ),
            if (detail != null)
              Text(
                detail.customerLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: WebTuiTypography.bodySmall.copyWith(
                  color: WebTuiColors.textSecondary,
                ),
              ),
          ],
        ),
        actions: [
          if (detail != null)
            PopupMenuButton<_TicketMenuAction>(
              key: const Key('customer_ticket_menu'),
              tooltip: tr('Thao tác ticket', 'Ticket actions'),
              icon: const Icon(Icons.more_vert_rounded),
              onSelected: (action) => _onMenu(action, state),
              itemBuilder: (context) => [
                if (canReply)
                  state.assignedToMe
                      ? PopupMenuItem(
                          value: _TicketMenuAction.release,
                          child: Text(tr('Bỏ nhận', 'Unassign me')),
                        )
                      : PopupMenuItem(
                          value: _TicketMenuAction.claim,
                          child: Text(tr('Nhận xử lý', 'Assign to me')),
                        ),
                if (canReply)
                  detail.ticket.status == CustomerTicketStatus.unanswered
                      ? PopupMenuItem(
                          value: _TicketMenuAction.markAnswered,
                          child: Text(tr('Đã xử lý', 'Done')),
                        )
                      : PopupMenuItem(
                          value: _TicketMenuAction.reopen,
                          child: Text(tr('Mở lại', 'Reopen')),
                        ),
                PopupMenuItem(
                  value: _TicketMenuAction.reload,
                  child: Text(tr('Tải lại', 'Reload')),
                ),
                if (detail.customer != null)
                  PopupMenuItem(
                    value: _TicketMenuAction.info,
                    child: Text(tr('Thông tin khách', 'Customer info')),
                  ),
              ],
            ),
        ],
      ),
      body: SafeArea(top: false, child: _body(state, canReply, now)),
    );
  }

  Widget _body(CustomerTicketDetailState state, bool canReply, DateTime now) {
    final detail = state.detail;
    if (state.forbidden) {
      return CustomerTicketNoAccessState(message: state.errorMessage);
    }
    if (detail == null) {
      if (state.errorMessage != null && !state.isLoading) {
        return WebTuiErrorState(
          title: tr('Không tải được ticket', 'Couldn\'t load the ticket'),
          message: state.errorMessage!,
          onRetry: () => unawaited(_controller.load()),
        );
      }
      return WebTuiLoadingState(
        message: tr('Đang tải ticket...', 'Loading ticket...'),
      );
    }
    final children = <Widget>[
      if (canReply)
        _AiDraftCard(
          draft: detail.aiDraft,
          pending: state.isDraftPending,
          errorMessage: state.aiErrorMessage,
          showRequest:
              detail.ticket.status == CustomerTicketStatus.unanswered ||
              detail.aiDraft != null,
          onUse: _useDraft,
          onRequest: _requestDraft,
          onDismissError: _controller.dismissAiError,
        ),
      for (final message in detail.messages.reversed)
        _TicketMessageBubble(
          message: message,
          now: now,
          onCopy: () => _copy(message.text),
        ),
      if (detail.ticket.truncated) const _TruncatedNote(),
    ];
    return Column(
      children: [
        _TicketHeader(state: state, detail: detail),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => _controller.load(silent: true),
            child: detail.messages.isEmpty && !canReply
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      WebTuiEmptyState(
                        title: tr('Chưa có tin nhắn', 'No messages yet'),
                        message: tr(
                          'Ticket này chưa có nội dung.',
                          'This ticket has no content yet.',
                        ),
                        icon: Icons.chat_bubble_outline_rounded,
                      ),
                    ],
                  )
                : ListView.separated(
                    key: const Key('customer_ticket_thread'),
                    reverse: true,
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(
                      WebTuiSpacing.md,
                      WebTuiSpacing.md,
                      WebTuiSpacing.md,
                      WebTuiSpacing.md,
                    ),
                    itemCount: children.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: WebTuiSpacing.md),
                    itemBuilder: (context, index) => children[index],
                  ),
          ),
        ),
        if (canReply)
          _Composer(
            controller: _composer,
            state: state,
            onSend: () => unawaited(_send()),
            onPickImages: () => unawaited(_pickImages()),
            onRemoveImage: _controller.removeImage,
          )
        else
          const _ReadOnlyNote(),
      ],
    );
  }

  Future<void> _send({bool force = false}) async {
    final outcome = await _controller.reply(_composer.text, force: force);
    if (!mounted) return;
    switch (outcome.status) {
      case CustomerTicketActionStatus.done:
        _composer.clear();
        _toast(outcome.message);
      case CustomerTicketActionStatus.claimedByOther:
        final confirmed = await _confirm(
          title: tr(
            'Ticket đang có người xử lý',
            'Someone is handling this ticket',
          ),
          message: tr(
            '${outcome.holderName} đang xử lý ticket này. Vẫn gửi?',
            '${outcome.holderName} is handling this ticket. Send anyway?',
          ),
          confirmLabel: tr('Vẫn gửi', 'Send anyway'),
        );
        if (confirmed && mounted) await _send(force: true);
      case CustomerTicketActionStatus.failed:
        _toast(outcome.message);
    }
  }

  Future<void> _claim({bool force = false}) async {
    final outcome = await _controller.claim(force: force);
    if (!mounted) return;
    switch (outcome.status) {
      case CustomerTicketActionStatus.done:
        _toast(outcome.message);
      case CustomerTicketActionStatus.claimedByOther:
        final confirmed = await _confirm(
          title: tr(
            'Ticket đang có người xử lý',
            'Someone is handling this ticket',
          ),
          message: tr(
            '${outcome.holderName} đang xử lý ticket này. Vẫn nhận xử lý?',
            '${outcome.holderName} is handling this ticket. Assign it to you anyway?',
          ),
          confirmLabel: tr('Nhận xử lý', 'Assign to me'),
        );
        if (confirmed && mounted) await _claim(force: true);
      case CustomerTicketActionStatus.failed:
        _toast(outcome.message);
    }
  }

  Future<void> _onMenu(
    _TicketMenuAction action,
    CustomerTicketDetailState state,
  ) async {
    switch (action) {
      case _TicketMenuAction.claim:
        await _claim();
      case _TicketMenuAction.release:
        _toast((await _controller.release()).message);
      case _TicketMenuAction.markAnswered:
        _toast(
          (await _controller.setStatus(CustomerTicketStatus.answered)).message,
        );
      case _TicketMenuAction.reopen:
        _toast(
          (await _controller.setStatus(
            CustomerTicketStatus.unanswered,
          )).message,
        );
      case _TicketMenuAction.reload:
        await _controller.load(silent: true);
      case _TicketMenuAction.info:
        final customer = state.detail?.customer;
        if (customer != null && mounted) {
          await _showCustomerInfo(context, customer);
        }
    }
  }

  Future<void> _pickImages() async {
    final source = await showWebTuiSheet<CustomerTicketImageSource>(
      context: context,
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          WebTuiSheetHeader(title: tr('Thêm ảnh', 'Add photo')),
          WebTuiSheetActionTile(
            icon: WebTuiIcons.gallery,
            title: tr('Chọn từ thư viện ảnh', 'Choose from photo library'),
            onTap: () => Navigator.of(
              sheetContext,
            ).pop(CustomerTicketImageSource.gallery),
          ),
          WebTuiSheetActionTile(
            icon: WebTuiIcons.camera,
            title: tr('Chụp ảnh', 'Take photo'),
            onTap: () => Navigator.of(
              sheetContext,
            ).pop(CustomerTicketImageSource.camera),
          ),
          const SizedBox(height: WebTuiSpacing.md),
        ],
      ),
    );
    if (source == null || !mounted) return;
    final message = await _controller.pickImages(source);
    if (mounted) _toast(message);
  }

  /// Chép nháp vào khung soạn để nhân viên sửa rồi tự bấm gửi.
  void _useDraft(String text) {
    _composer
      ..text = text
      ..selection = TextSelection.collapsed(offset: text.length);
  }

  Future<void> _requestDraft() async {
    final instruction = await _askInstruction(context);
    if (instruction == null || !mounted) return;
    final outcome = await _controller.requestAiDraft(instruction: instruction);
    if (mounted && outcome.status == CustomerTicketActionStatus.failed) {
      _toast(outcome.message);
    }
  }

  Future<void> _copy(String text) async {
    if (text.trim().isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    _toast(tr('Đã chép nội dung tin.', 'Message copied.'));
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    final confirmed = await showWebTuiConfirmDialog(
      context,
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      cancelLabel: tr('Huỷ', 'Cancel'),
      icon: WebTuiIcons.ticket,
    );
    return confirmed;
  }

  void _toast(String? message) {
    final text = message?.trim();
    if (text == null || text.isEmpty || !mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }
}

class _TicketHeader extends StatelessWidget {
  const _TicketHeader({required this.state, required this.detail});

  final CustomerTicketDetailState state;
  final CustomerTicketDetail detail;

  @override
  Widget build(BuildContext context) {
    final ticket = detail.ticket;
    final assignee = state.assignee;
    final status = customerTicketStatusLabel(ticket.status);
    return Container(
      width: double.infinity,
      color: WebTuiColors.surface,
      padding: const EdgeInsets.fromLTRB(
        WebTuiSpacing.lg,
        WebTuiSpacing.sm,
        WebTuiSpacing.lg,
        WebTuiSpacing.sm,
      ),
      child: Wrap(
        spacing: WebTuiSpacing.xs,
        runSpacing: WebTuiSpacing.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (ticket.service.isNotEmpty)
            WebTuiStatusPill(
              label: ticket.service,
              color: WebTuiColors.textSecondary,
            ),
          if (status.isNotEmpty)
            WebTuiStatusPill(
              label: status,
              color: ticket.status == CustomerTicketStatus.unanswered
                  ? WebTuiColors.accentAmber
                  : WebTuiColors.accentGreen,
            ),
          WebTuiStatusPill(
            label: assignee == null
                ? tr('Chưa ai nhận xử lý', 'No one is handling it')
                : state.assignedToMe
                ? tr('Bạn đang xử lý', 'You\'re handling it')
                : '${assignee.name.isEmpty ? tr('Người khác', 'Someone else') : assignee.name} đang xử lý',
            color: assignee == null
                ? WebTuiColors.textMuted
                : state.assignedToMe
                ? WebTuiColors.accentGreen
                : WebTuiColors.primary,
          ),
          if (state.isClaiming || state.isUpdatingStatus)
            const SizedBox.square(
              dimension: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
    );
  }
}

class _TicketMessageBubble extends StatelessWidget {
  const _TicketMessageBubble({
    required this.message,
    required this.now,
    required this.onCopy,
  });

  final CustomerTicketMessage message;
  final DateTime now;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final outgoing = message.fromStaff;
    final time = customerTicketMessageTime(message.time, now);
    final text = message.text.trim();
    return Column(
      crossAxisAlignment: outgoing
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: WebTuiSpacing.xs),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (message.isAssistant) ...[
                Icon(
                  Icons.smart_toy_outlined,
                  size: 14,
                  color: WebTuiColors.primary,
                ),
                const SizedBox(width: WebTuiSpacing.xxs),
              ],
              Flexible(
                child: Text(
                  message.displaySenderName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: WebTuiTypography.labelSmall.copyWith(
                    color: outgoing
                        ? WebTuiColors.primary
                        : WebTuiColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: WebTuiSpacing.xxs),
        if (text.isNotEmpty)
          GestureDetector(
            onLongPress: onCopy,
            child: WebTuiMessageBubble(
              text: text,
              timeLabel: time,
              outgoing: outgoing,
            ),
          ),
        if (message.images.isNotEmpty) ...[
          if (text.isNotEmpty) const SizedBox(height: WebTuiSpacing.xs),
          Wrap(
            spacing: WebTuiSpacing.xs,
            runSpacing: WebTuiSpacing.xs,
            alignment: outgoing ? WrapAlignment.end : WrapAlignment.start,
            children: [
              for (final url in message.images)
                Semantics(
                  button: true,
                  label: tr('Xem ảnh lớn', 'View full size'),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(WebTuiRadii.sm),
                    onTap: () => showCustomerTicketImageViewer(context, url),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(WebTuiRadii.sm),
                      child: CustomerTicketRemoteImage(
                        url: url,
                        width: 112,
                        height: 112,
                        semanticLabel: tr(
                          'Ảnh trong tin của ${message.displaySenderName}',
                          'Photo in message from ${message.displaySenderName}',
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (text.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: WebTuiSpacing.xxs),
              child: Text(
                time,
                style: WebTuiTypography.labelSmall.copyWith(
                  color: WebTuiColors.textMuted,
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _AiDraftCard extends StatelessWidget {
  const _AiDraftCard({
    required this.draft,
    required this.pending,
    required this.errorMessage,
    required this.showRequest,
    required this.onUse,
    required this.onRequest,
    required this.onDismissError,
  });

  final CustomerTicketAiDraft? draft;
  final bool pending;
  final String? errorMessage;
  final bool showRequest;
  final ValueChanged<String> onUse;
  final VoidCallback onRequest;
  final VoidCallback onDismissError;

  @override
  Widget build(BuildContext context) {
    final draft = this.draft;
    final error = errorMessage?.trim();
    if (draft == null && !pending && !showRequest && error == null) {
      return const SizedBox.shrink();
    }
    final percent = draft?.confidencePercent;
    final category = customerTicketCategoryLabel(draft?.category ?? '');
    return DecoratedBox(
      key: const Key('customer_ticket_ai_card'),
      decoration: BoxDecoration(
        color: WebTuiColors.surface,
        borderRadius: BorderRadius.circular(WebTuiRadii.md),
        border: Border.all(color: WebTuiColors.primary.withValues(alpha: 0.28)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(WebTuiSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.auto_awesome_outlined,
                  size: 18,
                  color: WebTuiColors.primary,
                ),
                const SizedBox(width: WebTuiSpacing.xs),
                Expanded(
                  child: Text(
                    draft == null
                        ? tr('Trợ lý AI', 'AI assistant')
                        : tr('Nháp AI', 'AI draft'),
                    style: WebTuiTypography.bodyMedium.copyWith(
                      color: WebTuiColors.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (pending)
                  const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            if (draft != null) ...[
              const SizedBox(height: WebTuiSpacing.xs),
              Wrap(
                spacing: WebTuiSpacing.xs,
                runSpacing: WebTuiSpacing.xs,
                children: [
                  if (percent != null)
                    WebTuiStatusPill(
                      label: tr('Tự tin $percent%', 'Confidence $percent%'),
                      color: percent >= 70
                          ? WebTuiColors.accentGreen
                          : WebTuiColors.accentAmber,
                    ),
                  if (category.isNotEmpty)
                    WebTuiStatusPill(
                      label: category,
                      color: WebTuiColors.textSecondary,
                    ),
                ],
              ),
              if (draft.needsHuman) ...[
                const SizedBox(height: WebTuiSpacing.sm),
                _Notice(
                  icon: Icons.warning_amber_rounded,
                  color: WebTuiColors.accentAmber,
                  text: draft.reason.isEmpty
                      ? tr(
                          'AI đề nghị người kiểm tra kỹ trước khi gửi.',
                          'AI suggests a careful human check before sending.',
                        )
                      : tr(
                          'Cần người xử lý: ${draft.reason}',
                          'Needs a person: ${draft.reason}',
                        ),
                ),
              ],
              const SizedBox(height: WebTuiSpacing.sm),
              SelectableText(
                draft.text,
                style: WebTuiTypography.bodyMedium.copyWith(
                  color: WebTuiColors.textPrimary,
                  height: 1.4,
                ),
              ),
              if (draft.suggestedCommand.isNotEmpty) ...[
                const SizedBox(height: WebTuiSpacing.xs),
                Text(
                  tr(
                    'Lệnh gợi ý: ${draft.suggestedCommand}',
                    'Suggested command: ${draft.suggestedCommand}',
                  ),
                  style: WebTuiTypography.bodySmall.copyWith(
                    color: WebTuiColors.textSecondary,
                  ),
                ),
              ],
              if (draft.model.isNotEmpty) ...[
                const SizedBox(height: WebTuiSpacing.xxs),
                Text(
                  draft.usedFallback
                      ? tr(
                          '${draft.model} (dự phòng)',
                          '${draft.model} (fallback)',
                        )
                      : draft.model,
                  style: WebTuiTypography.labelSmall.copyWith(
                    color: WebTuiColors.textMuted,
                  ),
                ),
              ],
            ] else if (pending) ...[
              const SizedBox(height: WebTuiSpacing.xs),
              Text(
                tr('AI đang soạn câu trả lời...', 'AI is drafting a reply...'),
                style: WebTuiTypography.bodySmall.copyWith(
                  color: WebTuiColors.textSecondary,
                ),
              ),
            ] else ...[
              const SizedBox(height: WebTuiSpacing.xs),
              Text(
                tr(
                  'Chưa có nháp cho tin mới nhất của khách.',
                  'No draft yet for the customer\'s latest message.',
                ),
                style: WebTuiTypography.bodySmall.copyWith(
                  color: WebTuiColors.textSecondary,
                ),
              ),
            ],
            if (error != null && error.isNotEmpty) ...[
              const SizedBox(height: WebTuiSpacing.sm),
              _Notice(
                icon: Icons.error_outline_rounded,
                color: WebTuiColors.danger,
                text: error,
                onClose: onDismissError,
              ),
            ],
            const SizedBox(height: WebTuiSpacing.sm),
            Wrap(
              spacing: WebTuiSpacing.sm,
              runSpacing: WebTuiSpacing.xs,
              children: [
                if (draft != null)
                  FilledButton.tonalIcon(
                    onPressed: () => onUse(draft.text),
                    icon: const Icon(Icons.edit_note_rounded, size: 18),
                    label: Text(tr('Dùng câu này', 'Use this reply')),
                  ),
                TextButton.icon(
                  onPressed: pending ? null : onRequest,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: Text(
                    draft == null
                        ? tr('AI soạn trả lời', 'Draft a reply with AI')
                        : tr('Soạn lại', 'Redraft'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.color,
    required this.text,
    this.onClose,
  });

  final IconData icon;
  final Color color;
  final String text;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(WebTuiRadii.sm),
      ),
      child: Padding(
        padding: const EdgeInsets.all(WebTuiSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: WebTuiSpacing.xs),
            Expanded(
              child: Text(
                text,
                style: WebTuiTypography.bodySmall.copyWith(
                  color: WebTuiColors.textPrimary,
                ),
              ),
            ),
            if (onClose != null)
              InkWell(
                onTap: onClose,
                child: Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: WebTuiColors.textMuted,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TruncatedNote extends StatelessWidget {
  const _TruncatedNote();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        tr(
          'Chỉ hiện các tin gần nhất của ticket.',
          'Only the latest messages of the ticket are shown.',
        ),
        style: WebTuiTypography.labelSmall.copyWith(
          color: WebTuiColors.textMuted,
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.state,
    required this.onSend,
    required this.onPickImages,
    required this.onRemoveImage,
  });

  final TextEditingController controller;
  final CustomerTicketDetailState state;
  final VoidCallback onSend;
  final VoidCallback onPickImages;
  final ValueChanged<int> onRemoveImage;

  @override
  Widget build(BuildContext context) {
    final images = state.images;
    final holder = state.heldByOther ? state.assignee?.name.trim() : null;
    return Material(
      color: WebTuiColors.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          WebTuiSpacing.sm,
          WebTuiSpacing.sm,
          WebTuiSpacing.sm,
          WebTuiSpacing.sm,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (holder != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  WebTuiSpacing.sm,
                  0,
                  WebTuiSpacing.sm,
                  WebTuiSpacing.xs,
                ),
                child: Text(
                  '${holder.isEmpty ? tr('Người khác', 'Someone else') : holder} đang xử lý ticket này.',
                  style: WebTuiTypography.bodySmall.copyWith(
                    color: WebTuiColors.accentAmber,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            if (images.isNotEmpty)
              SizedBox(
                height: 78,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  // Chừa chỗ cho nút bỏ ảnh nhô ra góc trên.
                  padding: const EdgeInsets.fromLTRB(
                    WebTuiSpacing.sm,
                    WebTuiSpacing.sm,
                    WebTuiSpacing.sm,
                    0,
                  ),
                  itemCount: images.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(width: WebTuiSpacing.sm),
                  itemBuilder: (context, index) => _PickedImage(
                    image: images[index],
                    onRemove: state.isSending
                        ? null
                        : () => onRemoveImage(index),
                  ),
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  key: const Key('customer_ticket_attach'),
                  tooltip: tr(
                    'Đính kèm ảnh (tối đa 3)',
                    'Attach photos (up to 3)',
                  ),
                  onPressed:
                      state.isSending ||
                          state.isPickingImages ||
                          images.length >= customerTicketMaxImages
                      ? null
                      : onPickImages,
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  color: WebTuiColors.primary,
                ),
                Expanded(
                  child: TextField(
                    key: const Key('customer_ticket_composer'),
                    controller: controller,
                    enabled: !state.isSending,
                    minLines: 1,
                    maxLines: 5,
                    maxLength: customerTicketMaxReplyLength,
                    maxLengthEnforcement: MaxLengthEnforcement.enforced,
                    textCapitalization: TextCapitalization.sentences,
                    keyboardType: TextInputType.multiline,
                    buildCounter:
                        (
                          context, {
                          required currentLength,
                          required isFocused,
                          required maxLength,
                        }) => currentLength > 3600
                        ? Text('$currentLength/$maxLength')
                        : null,
                    decoration: InputDecoration(
                      hintText: tr(
                        'Nhập câu trả lời cho khách...',
                        'Type a reply to the customer...',
                      ),
                      isDense: true,
                      filled: true,
                      fillColor: WebTuiColors.backgroundMuted,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: WebTuiSpacing.md,
                        vertical: WebTuiSpacing.sm + 2,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                        borderSide: BorderSide(color: WebTuiColors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                        borderSide: BorderSide(color: WebTuiColors.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                        borderSide: BorderSide(color: WebTuiColors.primary),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: WebTuiSpacing.xs),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: controller,
                  builder: (context, value, _) {
                    final ready =
                        !state.isSending &&
                        (value.text.trim().isNotEmpty || images.isNotEmpty);
                    return IconButton.filled(
                      key: const Key('customer_ticket_send'),
                      tooltip: tr('Gửi trả lời', 'Send reply'),
                      onPressed: ready ? onSend : null,
                      icon: state.isSending
                          ? SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: WebTuiColors.textOnPrimary,
                              ),
                            )
                          : const Icon(Icons.send_rounded),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PickedImage extends StatelessWidget {
  const _PickedImage({required this.image, required this.onRemove});

  final CustomerTicketImageUpload image;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(WebTuiRadii.sm),
          child: CustomerTicketLocalImage(image: image, size: 64),
        ),
        Positioned(
          top: -6,
          right: -6,
          child: Material(
            color: WebTuiColors.textPrimary,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onRemove,
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: Icon(
                  Icons.close_rounded,
                  size: 14,
                  color: onRemove == null
                      ? WebTuiColors.textMuted
                      : WebTuiColors.textOnPrimary,
                  semanticLabel: tr(
                    'Bỏ ảnh ${image.name}',
                    'Remove photo ${image.name}',
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ReadOnlyNote extends StatelessWidget {
  const _ReadOnlyNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('customer_ticket_read_only'),
      width: double.infinity,
      color: WebTuiColors.surface,
      padding: const EdgeInsets.all(WebTuiSpacing.md),
      child: Row(
        children: [
          Icon(
            Icons.visibility_outlined,
            size: 18,
            color: WebTuiColors.textMuted,
          ),
          const SizedBox(width: WebTuiSpacing.sm),
          Expanded(
            child: Text(
              tr(
                'Chỉ xem: bạn chưa có quyền trả lời ticket khách.',
                'View only: you don\'t have permission to reply to customer tickets.',
              ),
              style: WebTuiTypography.bodySmall.copyWith(
                color: WebTuiColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Hỏi gợi ý cho AI (không bắt buộc); `null` khi người dùng huỷ.
Future<String?> _askInstruction(BuildContext context) {
  return showWebTuiSheet<String>(
    context: context,
    builder: (sheetContext) => const _InstructionSheet(),
  );
}

class _InstructionSheet extends StatefulWidget {
  const _InstructionSheet();

  @override
  State<_InstructionSheet> createState() => _InstructionSheetState();
}

class _InstructionSheetState extends State<_InstructionSheet> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, WebTuiSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WebTuiSheetHeader(
            title: tr('AI soạn câu trả lời', 'Draft a reply with AI'),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: WebTuiSpacing.lg),
            child: WebTuiDialogTextField(
              key: const Key('customer_ticket_ai_instruction'),
              controller: _controller,
              autofocus: true,
              maxLength: customerTicketMaxInstructionLength,
              hint: tr(
                'Gợi ý cho AI (không bắt buộc), vd. xin lỗi khách, hẹn 30 phút',
                'Hint for the AI (optional), e.g. apologize to the customer, promise 30 minutes',
              ),
            ),
          ),
          const SizedBox(height: WebTuiSpacing.sm),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: WebTuiSpacing.lg),
            child: FilledButton.icon(
              onPressed: () =>
                  Navigator.of(context).pop(_controller.text.trim()),
              icon: const Icon(Icons.auto_awesome_outlined),
              label: Text(tr('Soạn nháp', 'Draft')),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _showCustomerInfo(
  BuildContext context,
  CustomerTicketCustomer customer,
) {
  return showWebTuiSheet<void>(
    context: context,
    builder: (sheetContext) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.92,
      builder: (context, scrollController) => ListView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(
          WebTuiSpacing.lg,
          0,
          WebTuiSpacing.lg,
          WebTuiSpacing.xl,
        ),
        children: [
          WebTuiSheetHeader(title: tr('Thông tin khách', 'Customer info')),
          _InfoRow(label: tr('Tên', 'Name'), value: customer.name),
          _InfoRow(label: 'Email', value: customer.email),
          _InfoRow(
            label: tr('Mã khách', 'Customer ID'),
            value: customer.customerId == null ? '' : '#${customer.customerId}',
          ),
          _InfoRow(
            label: tr('Số dư', 'Balance'),
            value: customer.balance == null
                ? ''
                : formatCustomerTicketMoney(customer.balance!),
          ),
          const SizedBox(height: WebTuiSpacing.md),
          Text(
            customer.servicesTotal > customer.services.length
                ? tr(
                    'Dịch vụ (${customer.services.length}/${customer.servicesTotal})',
                    'Services (${customer.services.length}/${customer.servicesTotal})',
                  )
                : tr(
                    'Dịch vụ (${customer.services.length})',
                    'Services (${customer.services.length})',
                  ),
            style: WebTuiTypography.bodyMedium.copyWith(
              color: WebTuiColors.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: WebTuiSpacing.xs),
          if (customer.services.isEmpty)
            Text(
              tr('Khách chưa có dịch vụ.', 'The customer has no services.'),
              style: WebTuiTypography.bodySmall.copyWith(
                color: WebTuiColors.textMuted,
              ),
            )
          else
            for (final service in customer.services)
              _ServiceRow(service: service),
        ],
      ),
    ),
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: WebTuiSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: WebTuiTypography.bodySmall.copyWith(
                color: WebTuiColors.textMuted,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: WebTuiTypography.bodyMedium.copyWith(
                color: WebTuiColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ServiceRow extends StatelessWidget {
  const _ServiceRow({required this.service});

  final CustomerTicketService service;

  @override
  Widget build(BuildContext context) {
    final expires = customerTicketDate(service.expiresAt);
    final days = service.daysRemaining;
    final details = [
      if (service.type.isNotEmpty) service.type,
      if (service.meta.isNotEmpty) service.meta,
      if (expires.isNotEmpty)
        days == null
            ? tr('Hạn $expires', 'Expires $expires')
            : days < 0
            ? tr('Hết hạn $expires', 'Expired $expires')
            : tr(
                'Hạn $expires (còn $days ngày)',
                'Expires $expires ($days days left)',
              ),
      service.autoRenew
          ? tr('Tự gia hạn', 'Auto-renews')
          : tr('Không tự gia hạn', 'Doesn\'t auto-renew'),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: WebTuiSpacing.xs),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: WebTuiColors.surfaceElevated,
          borderRadius: BorderRadius.circular(WebTuiRadii.sm),
          border: Border.all(color: WebTuiColors.border),
        ),
        child: Padding(
          padding: const EdgeInsets.all(WebTuiSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      service.name.isEmpty ? '#${service.id}' : service.name,
                      style: WebTuiTypography.bodyMedium.copyWith(
                        color: WebTuiColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (service.status.isNotEmpty)
                    WebTuiStatusPill(
                      label: customerTicketServiceStatusLabel(service.status),
                      color: WebTuiColors.textSecondary,
                    ),
                ],
              ),
              const SizedBox(height: WebTuiSpacing.xxs),
              Text(
                details.join(' · '),
                style: WebTuiTypography.bodySmall.copyWith(
                  color: WebTuiColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

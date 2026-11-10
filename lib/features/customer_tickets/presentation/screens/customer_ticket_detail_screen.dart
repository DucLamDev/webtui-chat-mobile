import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../design_system/components/webtui_components.dart';
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
        body: const WebTuiEmptyState(
          title: 'Chưa chọn workspace',
          message: 'Chọn workspace trước khi xem ticket khách.',
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
        title: Text(ticketId.isEmpty ? 'Ticket khách' : '#$ticketId'),
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
      tooltip: 'Quay lại',
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
              tooltip: 'Thao tác ticket',
              icon: const Icon(Icons.more_vert_rounded),
              onSelected: (action) => _onMenu(action, state),
              itemBuilder: (context) => [
                if (canReply)
                  state.assignedToMe
                      ? const PopupMenuItem(
                          value: _TicketMenuAction.release,
                          child: Text('Bỏ nhận'),
                        )
                      : const PopupMenuItem(
                          value: _TicketMenuAction.claim,
                          child: Text('Nhận xử lý'),
                        ),
                if (canReply)
                  detail.ticket.status == CustomerTicketStatus.unanswered
                      ? const PopupMenuItem(
                          value: _TicketMenuAction.markAnswered,
                          child: Text('Đã xử lý'),
                        )
                      : const PopupMenuItem(
                          value: _TicketMenuAction.reopen,
                          child: Text('Mở lại'),
                        ),
                const PopupMenuItem(
                  value: _TicketMenuAction.reload,
                  child: Text('Tải lại'),
                ),
                if (detail.customer != null)
                  const PopupMenuItem(
                    value: _TicketMenuAction.info,
                    child: Text('Thông tin khách'),
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
          title: 'Không tải được ticket',
          message: state.errorMessage!,
          onRetry: () => unawaited(_controller.load()),
        );
      }
      return const WebTuiLoadingState(message: 'Đang tải ticket...');
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
                    children: const [
                      WebTuiEmptyState(
                        title: 'Chưa có tin nhắn',
                        message: 'Ticket này chưa có nội dung.',
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
          title: 'Ticket đang có người xử lý',
          message: '${outcome.holderName} đang xử lý ticket này. Vẫn gửi?',
          confirmLabel: 'Vẫn gửi',
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
          title: 'Ticket đang có người xử lý',
          message:
              '${outcome.holderName} đang xử lý ticket này. Vẫn nhận xử lý?',
          confirmLabel: 'Nhận xử lý',
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
    final source = await showModalBottomSheet<CustomerTicketImageSource>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Chọn từ thư viện ảnh'),
              onTap: () => Navigator.of(
                sheetContext,
              ).pop(CustomerTicketImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Chụp ảnh'),
              onTap: () => Navigator.of(
                sheetContext,
              ).pop(CustomerTicketImageSource.camera),
            ),
          ],
        ),
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
    _toast('Đã chép nội dung tin.');
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return confirmed ?? false;
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
                ? 'Chưa ai nhận xử lý'
                : state.assignedToMe
                ? 'Bạn đang xử lý'
                : '${assignee.name.isEmpty ? 'Người khác' : assignee.name} đang xử lý',
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
                const Icon(
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
                  label: 'Xem ảnh lớn',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(WebTuiRadii.sm),
                    onTap: () => showCustomerTicketImageViewer(context, url),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(WebTuiRadii.sm),
                      child: CustomerTicketRemoteImage(
                        url: url,
                        width: 112,
                        height: 112,
                        semanticLabel:
                            'Ảnh trong tin của '
                            '${message.displaySenderName}',
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
                const Icon(
                  Icons.auto_awesome_outlined,
                  size: 18,
                  color: WebTuiColors.primary,
                ),
                const SizedBox(width: WebTuiSpacing.xs),
                Expanded(
                  child: Text(
                    draft == null ? 'Trợ lý AI' : 'Nháp AI',
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
                      label: 'Tự tin $percent%',
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
                      ? 'AI đề nghị người kiểm tra kỹ trước khi gửi.'
                      : 'Cần người xử lý: ${draft.reason}',
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
                  'Lệnh gợi ý: ${draft.suggestedCommand}',
                  style: WebTuiTypography.bodySmall.copyWith(
                    color: WebTuiColors.textSecondary,
                  ),
                ),
              ],
              if (draft.model.isNotEmpty) ...[
                const SizedBox(height: WebTuiSpacing.xxs),
                Text(
                  draft.usedFallback
                      ? '${draft.model} (dự phòng)'
                      : draft.model,
                  style: WebTuiTypography.labelSmall.copyWith(
                    color: WebTuiColors.textMuted,
                  ),
                ),
              ],
            ] else if (pending) ...[
              const SizedBox(height: WebTuiSpacing.xs),
              Text(
                'AI đang soạn câu trả lời...',
                style: WebTuiTypography.bodySmall.copyWith(
                  color: WebTuiColors.textSecondary,
                ),
              ),
            ] else ...[
              const SizedBox(height: WebTuiSpacing.xs),
              Text(
                'Chưa có nháp cho tin mới nhất của khách.',
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
                    label: const Text('Dùng câu này'),
                  ),
                TextButton.icon(
                  onPressed: pending ? null : onRequest,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: Text(draft == null ? 'AI soạn trả lời' : 'Soạn lại'),
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
                child: const Icon(
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
        'Chỉ hiện các tin gần nhất của ticket.',
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
                  '${holder.isEmpty ? 'Người khác' : holder} đang xử lý ticket này.',
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
                  tooltip: 'Đính kèm ảnh (tối đa 3)',
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
                      hintText: 'Nhập câu trả lời cho khách...',
                      isDense: true,
                      filled: true,
                      fillColor: WebTuiColors.backgroundMuted,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: WebTuiSpacing.md,
                        vertical: WebTuiSpacing.sm + 2,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                        borderSide: const BorderSide(
                          color: WebTuiColors.border,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                        borderSide: const BorderSide(
                          color: WebTuiColors.border,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                        borderSide: const BorderSide(
                          color: WebTuiColors.primary,
                        ),
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
                      tooltip: 'Gửi trả lời',
                      onPressed: ready ? onSend : null,
                      icon: state.isSending
                          ? const SizedBox.square(
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
                  semanticLabel: 'Bỏ ảnh ${image.name}',
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
          const Icon(
            Icons.visibility_outlined,
            size: 18,
            color: WebTuiColors.textMuted,
          ),
          const SizedBox(width: WebTuiSpacing.sm),
          Expanded(
            child: Text(
              'Chỉ xem: bạn chưa có quyền trả lời ticket khách.',
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
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
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
      padding: EdgeInsets.fromLTRB(
        WebTuiSpacing.lg,
        0,
        WebTuiSpacing.lg,
        MediaQuery.viewInsetsOf(context).bottom + WebTuiSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'AI soạn câu trả lời',
            style: WebTuiTypography.titleMedium.copyWith(
              color: WebTuiColors.textPrimary,
            ),
          ),
          const SizedBox(height: WebTuiSpacing.sm),
          TextField(
            key: const Key('customer_ticket_ai_instruction'),
            controller: _controller,
            autofocus: true,
            minLines: 2,
            maxLines: 4,
            maxLength: customerTicketMaxInstructionLength,
            decoration: const InputDecoration(
              hintText:
                  'Gợi ý cho AI (không bắt buộc), vd. xin lỗi khách, hẹn 30 phút',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: WebTuiSpacing.sm),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
            icon: const Icon(Icons.auto_awesome_outlined),
            label: const Text('Soạn nháp'),
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
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
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
          Text(
            'Thông tin khách',
            style: WebTuiTypography.titleMedium.copyWith(
              color: WebTuiColors.textPrimary,
            ),
          ),
          const SizedBox(height: WebTuiSpacing.md),
          _InfoRow(label: 'Tên', value: customer.name),
          _InfoRow(label: 'Email', value: customer.email),
          _InfoRow(
            label: 'Mã khách',
            value: customer.customerId == null ? '' : '#${customer.customerId}',
          ),
          _InfoRow(
            label: 'Số dư',
            value: customer.balance == null
                ? ''
                : formatCustomerTicketMoney(customer.balance!),
          ),
          const SizedBox(height: WebTuiSpacing.md),
          Text(
            customer.servicesTotal > customer.services.length
                ? 'Dịch vụ (${customer.services.length}/${customer.servicesTotal})'
                : 'Dịch vụ (${customer.services.length})',
            style: WebTuiTypography.bodyMedium.copyWith(
              color: WebTuiColors.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: WebTuiSpacing.xs),
          if (customer.services.isEmpty)
            Text(
              'Khách chưa có dịch vụ.',
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
            ? 'Hạn $expires'
            : days < 0
            ? 'Hết hạn $expires'
            : 'Hạn $expires (còn $days ngày)',
      service.autoRenew ? 'Tự gia hạn' : 'Không tự gia hạn',
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

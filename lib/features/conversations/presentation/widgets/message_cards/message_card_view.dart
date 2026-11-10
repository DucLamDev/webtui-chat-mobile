import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../app/providers/foundation_providers.dart';
import '../../../../../design_system/components/webtui_badges.dart';
import '../../../../../design_system/tokens/webtui_colors.dart';
import '../../../../../design_system/tokens/webtui_radii.dart';
import '../../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../../design_system/tokens/webtui_typography.dart';
import '../../../domain/entities/chat_message.dart';
import '../../../domain/entities/message_card.dart';
import '../../controllers/message_card_controller.dart';
import 'card_chart.dart';
import 'card_common.dart';
import 'card_diagram.dart';
import 'card_form.dart';
import 'card_sections.dart';
import 'card_table.dart';

/// Máy chủ có hiểu thẻ bản 2 / nút `callback` / biểu mẫu không (theo discovery).
final richCardsEnabledProvider = Provider.autoDispose<bool>((ref) {
  return ref.watch(
    activeServerDiscoveryProvider.select(
      (discovery) => discovery?.capabilities.richCardsV2 ?? false,
    ),
  );
});

/// Thẻ của tin bot / sự kiện. Nút `reply` gửi tin qua [onReply] (`null` = khung
/// chat đang bị chặn, ẩn nút gửi); nút `copy` chép vào bộ nhớ tạm; nút
/// `callback`, phê duyệt và biểu mẫu chỉ hiện khi máy chủ báo `rich_cards_v2`.
class MessageCardView extends ConsumerStatefulWidget {
  const MessageCardView({
    required this.message,
    required this.card,
    required this.timeLabel,
    this.onReply,
    super.key,
  });

  final ChatMessage message;
  final MessageCard card;
  final String timeLabel;
  final ValueChanged<String>? onReply;

  @override
  ConsumerState<MessageCardView> createState() => _MessageCardViewState();
}

class _MessageCardViewState extends ConsumerState<MessageCardView> {
  MessageCardScope get _scope => MessageCardScope(
    workspaceId: widget.message.workspaceId,
    channelId: widget.message.channelId,
    messageId: widget.message.id,
  );

  bool get _needsInteractions =>
      widget.card.hasServerInteractions && ref.read(richCardsEnabledProvider);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_needsInteractions) return;
      unawaited(
        ref
            .read(messageCardControllerProvider(_scope).notifier)
            .loadInteractions(),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final card = widget.card;
    final interactive = ref.watch(richCardsEnabledProvider);
    final usesController = interactive && card.hasServerInteractions;
    final cardState = usesController
        ? ref.watch(messageCardControllerProvider(_scope))
        : const MessageCardState();
    if (usesController) {
      ref.listen(messageCardControllerProvider(_scope), (previous, next) {
        final message = next.errorMessage ?? next.noticeMessage;
        if (message == null ||
            (message == previous?.errorMessage ||
                message == previous?.noticeMessage)) {
          return;
        }
        ScaffoldMessenger.maybeOf(context)
          ?..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(message)));
      });
    }
    final toneColor = messageCardToneColor(card.tone);
    final statusLabel =
        card.statusLabel ?? messageCardDefaultStatusLabel(card.tone);
    final sections = [
      for (final section in card.sections)
        if (section is! MessageCardFormSection || interactive) section,
    ];
    final actions = [
      for (final action in card.actions)
        if (_isActionVisible(action, interactive)) action,
    ];
    final maxWidth = (MediaQuery.sizeOf(context).width * 0.86).clamp(
      260.0,
      440.0,
    );

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth, minWidth: 240),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: WebTuiColors.surface,
          borderRadius: BorderRadius.circular(WebTuiRadii.lg),
          border: Border.all(color: WebTuiColors.border),
          boxShadow: [
            BoxShadow(
              color: WebTuiColors.textPrimary.withValues(alpha: 0.06),
              blurRadius: 18,
              offset: const Offset(0, 7),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(WebTuiRadii.lg),
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: toneColor, width: 3)),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                WebTuiSpacing.md,
                WebTuiSpacing.md,
                WebTuiSpacing.md,
                WebTuiSpacing.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _Header(
                    card: card,
                    toneColor: toneColor,
                    statusLabel: statusLabel,
                  ),
                  if (card.summary != null) ...[
                    const SizedBox(height: WebTuiSpacing.sm),
                    Text(
                      card.summary!,
                      style: WebTuiTypography.bodySmall.copyWith(
                        color: WebTuiColors.textPrimary,
                        height: 1.4,
                      ),
                    ),
                  ],
                  if (card.facts.isNotEmpty) ...[
                    const SizedBox(height: WebTuiSpacing.md),
                    MessageCardFactsView(facts: card.facts),
                  ],
                  for (final section in sections) ...[
                    const SizedBox(height: WebTuiSpacing.md),
                    if (section.title.isNotEmpty)
                      MessageCardSectionTitle(section.title),
                    _sectionBody(section, cardState),
                  ],
                  if (actions.isNotEmpty) ...[
                    const SizedBox(height: WebTuiSpacing.md),
                    Wrap(
                      spacing: WebTuiSpacing.sm,
                      runSpacing: WebTuiSpacing.xs,
                      children: [
                        for (final action in actions)
                          _ActionButton(
                            action: action,
                            state: cardState,
                            onPressed: () => _onAction(action),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: WebTuiSpacing.xs),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      widget.timeLabel,
                      style: WebTuiTypography.labelSmall.copyWith(
                        color: WebTuiColors.textMuted,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool _isActionVisible(MessageCardAction action, bool interactive) {
    return switch (action) {
      MessageCardReplyAction() => widget.onReply != null,
      MessageCardCopyAction() => true,
      MessageCardCallbackAction() || MessageCardApprovalAction() => interactive,
    };
  }

  Widget _sectionBody(MessageCardSection section, MessageCardState cardState) {
    return switch (section) {
      MessageCardFactsSection(:final facts) => MessageCardFactsView(
        facts: facts,
      ),
      MessageCardRowsSection(:final rows) => MessageCardRowsView(rows: rows),
      MessageCardItemsSection(:final items) => MessageCardItemsView(
        items: items,
      ),
      MessageCardCommandsSection(:final commands) => MessageCardCommandsView(
        commands: commands,
      ),
      MessageCardChartSection(:final chart) => MessageCardChartView(
        chart: chart,
      ),
      MessageCardDiagramSection(:final diagram) => MessageCardDiagramView(
        diagram: diagram,
      ),
      MessageCardPlanSection(:final plan) => MessageCardPlanView(plan: plan),
      MessageCardTableSection(:final table) => MessageCardTableView(
        table: table,
      ),
      MessageCardFormSection(:final form) => MessageCardFormView(
        key: ValueKey('card-form-${form.formId}'),
        form: form,
        submittedAt: cardState.submittedForms[form.formId],
        submitting: cardState.submittingFormIds.contains(form.formId),
        serverFieldErrors: cardState.fieldErrors[form.formId] ?? const {},
        errorMessage: cardState.formErrors[form.formId],
        onSubmit: (values) => ref
            .read(messageCardControllerProvider(_scope).notifier)
            .submitForm(form, values),
      ),
    };
  }

  Future<void> _onAction(MessageCardAction action) async {
    switch (action) {
      case MessageCardReplyAction(:final reply):
        widget.onReply?.call(reply);
      case MessageCardCopyAction(:final copy):
        await Clipboard.setData(ClipboardData(text: copy));
        if (!mounted) return;
        ScaffoldMessenger.maybeOf(context)
          ?..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(content: Text('Đã chép vào bộ nhớ tạm.')),
          );
      case MessageCardCallbackAction(:final confirm):
        final provider = messageCardControllerProvider(_scope);
        if (ref.read(provider).isActionLocked(action.actionId)) return;
        final controller = ref.read(provider.notifier);
        if (confirm != null && !await _confirm(confirm, action.label)) return;
        if (!mounted) return;
        await controller.invokeAction(action);
      case MessageCardApprovalAction():
        await ref
            .read(messageCardControllerProvider(_scope).notifier)
            .decideApproval(action);
    }
  }

  Future<bool> _confirm(String question, String label) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(question),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(label),
          ),
        ],
      ),
    );
    return confirmed == true;
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.card,
    required this.toneColor,
    required this.statusLabel,
  });

  final MessageCard card;
  final Color toneColor;
  final String? statusLabel;

  @override
  Widget build(BuildContext context) {
    final subtitle = card.subtitle;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(messageCardToneIcon(card.tone), color: toneColor, size: 20),
        const SizedBox(width: WebTuiSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                card.title,
                style: WebTuiTypography.bodyMedium.copyWith(
                  color: WebTuiColors.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (subtitle != null)
                Text.rich(
                  TextSpan(
                    children: [
                      for (final (index, part)
                          in subtitle.split(' · ').indexed) ...[
                        if (index > 0) const TextSpan(text: ' · '),
                        TextSpan(
                          text: part,
                          style: part.trimLeft().startsWith('/')
                              ? const TextStyle(fontFamily: 'monospace')
                              : null,
                        ),
                      ],
                    ],
                  ),
                  style: WebTuiTypography.labelSmall.copyWith(
                    color: WebTuiColors.textSecondary,
                  ),
                ),
            ],
          ),
        ),
        if (statusLabel != null) ...[
          const SizedBox(width: WebTuiSpacing.sm),
          Flexible(
            flex: 0,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 120),
              child: WebTuiStatusPill(label: statusLabel!, color: toneColor),
            ),
          ),
        ],
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.action,
    required this.state,
    required this.onPressed,
  });

  final MessageCardAction action;
  final MessageCardState state;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final (pending, done) = switch (action) {
      MessageCardCallbackAction(:final actionId) => (
        state.pendingActionIds.contains(actionId),
        state.invokedActionIds.contains(actionId),
      ),
      MessageCardApprovalAction(:final approvalId) => (
        state.pendingApprovalIds.contains(approvalId),
        state.decidedApprovalIds.contains(approvalId),
      ),
      _ => (false, false),
    };
    final enabled = !pending && !done;
    final color = switch (action.tone) {
      MessageCardActionTone.primary => WebTuiColors.primary,
      MessageCardActionTone.danger => WebTuiColors.danger,
      MessageCardActionTone.neutral => WebTuiColors.textSecondary,
    };
    final icon = pending
        ? const SizedBox.square(
            dimension: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Icon(switch (action) {
            _ when done => Icons.check_rounded,
            MessageCardCopyAction() => Icons.copy_rounded,
            MessageCardReplyAction() => Icons.reply_rounded,
            MessageCardApprovalAction(
              decision: MessageCardApprovalDecision.approve,
            ) =>
              Icons.thumb_up_alt_outlined,
            MessageCardApprovalAction() => Icons.thumb_down_alt_outlined,
            MessageCardCallbackAction() => Icons.touch_app_outlined,
          }, size: 16);
    final label = Text(
      action.label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    final style = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(44, 40)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: WebTuiSpacing.md),
      ),
      visualDensity: VisualDensity.compact,
    );
    if (action.tone == MessageCardActionTone.neutral) {
      return OutlinedButton.icon(
        onPressed: enabled ? onPressed : null,
        style: style.copyWith(foregroundColor: WidgetStatePropertyAll(color)),
        icon: icon,
        label: label,
      );
    }
    return FilledButton.icon(
      onPressed: enabled ? onPressed : null,
      style: style.copyWith(
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? WebTuiColors.backgroundMuted
              : color,
        ),
      ),
      icon: icon,
      label: label,
    );
  }
}

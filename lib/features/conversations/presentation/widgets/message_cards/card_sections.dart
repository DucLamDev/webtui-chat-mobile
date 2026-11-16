import 'package:flutter/material.dart';

import '../../../../../design_system/tokens/webtui_colors.dart';
import '../../../../../design_system/tokens/webtui_radii.dart';
import '../../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../../design_system/tokens/webtui_typography.dart';
import '../../../../../l10n/app_strings.dart';
import '../../../domain/entities/message_card.dart';
import 'card_common.dart';

/// Lưới số liệu `Nhãn / giá trị`; số `emphasis` in to.
class MessageCardFactsView extends StatelessWidget {
  const MessageCardFactsView({required this.facts, super.key});

  final List<MessageCardFact> facts;

  @override
  Widget build(BuildContext context) {
    if (facts.isEmpty) {
      return MessageCardEmptyNote(tr('Chưa có số liệu.', 'No figures yet.'));
    }
    return Wrap(
      spacing: WebTuiSpacing.md,
      runSpacing: WebTuiSpacing.sm,
      children: [
        for (final fact in facts)
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 96, maxWidth: 260),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  fact.label,
                  style: WebTuiTypography.labelSmall.copyWith(
                    color: WebTuiColors.textMuted,
                  ),
                ),
                const SizedBox(height: WebTuiSpacing.xxs),
                Text(
                  fact.value,
                  style:
                      (fact.emphasis
                              ? WebTuiTypography.titleMedium
                              : WebTuiTypography.bodySmall)
                          .copyWith(
                            color: WebTuiColors.textPrimary,
                            fontWeight: fact.emphasis
                                ? FontWeight.w800
                                : FontWeight.w600,
                          ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Hàng `tiêu đề | chi tiết | ...`: phần đầu đậm, phần sau nhạt.
class MessageCardRowsView extends StatelessWidget {
  const MessageCardRowsView({required this.rows, super.key});

  final List<String> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return MessageCardEmptyNote(tr('Chưa có dữ liệu.', 'No data yet.'));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < rows.length; index++) ...[
          if (index > 0)
            Divider(height: WebTuiSpacing.md, color: WebTuiColors.border),
          _RowLine(parts: _split(rows[index])),
        ],
      ],
    );
  }

  static List<String> _split(String row) => row
      .split('|')
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
}

class _RowLine extends StatelessWidget {
  const _RowLine({required this.parts});

  final List<String> parts;

  @override
  Widget build(BuildContext context) {
    if (parts.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          parts.first,
          style: WebTuiTypography.bodySmall.copyWith(
            color: WebTuiColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (parts.length > 1)
          Text(
            parts.skip(1).join(' · '),
            style: WebTuiTypography.labelSmall.copyWith(
              color: WebTuiColors.textSecondary,
            ),
          ),
      ],
    );
  }
}

class MessageCardItemsView extends StatelessWidget {
  const MessageCardItemsView({required this.items, super.key});

  final List<String> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return MessageCardEmptyNote(tr('Chưa có mục nào.', 'No items yet.'));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: WebTuiSpacing.xxs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '•  ',
                  style: WebTuiTypography.bodySmall.copyWith(
                    color: WebTuiColors.textMuted,
                  ),
                ),
                Expanded(
                  child: Text(
                    item,
                    style: WebTuiTypography.bodySmall.copyWith(
                      color: WebTuiColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Lệnh gợi ý dạng mã (chỉ xem / chọn chép, không tự gửi).
class MessageCardCommandsView extends StatelessWidget {
  const MessageCardCommandsView({required this.commands, super.key});

  final List<String> commands;

  @override
  Widget build(BuildContext context) {
    if (commands.isEmpty) {
      return MessageCardEmptyNote(
        tr('Chưa có lệnh gợi ý.', 'No suggested commands yet.'),
      );
    }
    return Wrap(
      spacing: WebTuiSpacing.xs,
      runSpacing: WebTuiSpacing.xs,
      children: [
        for (final command in commands)
          DecoratedBox(
            decoration: BoxDecoration(
              color: WebTuiColors.backgroundMuted,
              borderRadius: BorderRadius.circular(WebTuiRadii.xs),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              child: Text(
                command,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: WebTuiColors.textPrimary,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Kế hoạch: danh sách bước có trạng thái, người làm, hạn.
class MessageCardPlanView extends StatelessWidget {
  const MessageCardPlanView({required this.plan, super.key});

  final MessageCardPlan plan;

  @override
  Widget build(BuildContext context) {
    final steps = plan.steps;
    if (steps.isEmpty) {
      return MessageCardEmptyNote(
        tr('Kế hoạch chưa có bước.', 'This plan has no steps yet.'),
      );
    }
    final done = steps
        .where((step) => step.status == MessageCardPlanStatus.done)
        .length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: WebTuiSpacing.xs),
          child: Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: done / steps.length,
                    minHeight: 6,
                    color: WebTuiColors.accentGreen,
                    backgroundColor: WebTuiColors.backgroundMuted,
                  ),
                ),
              ),
              const SizedBox(width: WebTuiSpacing.sm),
              Text(
                tr(
                  '$done/${steps.length} bước xong',
                  '$done/${steps.length} steps done',
                ),
                style: WebTuiTypography.labelSmall.copyWith(
                  color: WebTuiColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        for (final step in steps) _PlanStepTile(step: step),
      ],
    );
  }
}

class _PlanStepTile extends StatelessWidget {
  const _PlanStepTile({required this.step});

  final MessageCardPlanStep step;

  @override
  Widget build(BuildContext context) {
    final (icon, color, label) = switch (step.status) {
      MessageCardPlanStatus.done => (
        Icons.check_circle_rounded,
        WebTuiColors.accentGreen,
        tr('Xong', 'Done'),
      ),
      MessageCardPlanStatus.inProgress => (
        Icons.timelapse_rounded,
        WebTuiColors.primary,
        tr('Đang làm', 'In progress'),
      ),
      MessageCardPlanStatus.blocked => (
        Icons.block_rounded,
        WebTuiColors.danger,
        tr('Bị chặn', 'Blocked'),
      ),
      MessageCardPlanStatus.skipped => (
        Icons.remove_circle_outline_rounded,
        WebTuiColors.textMuted,
        tr('Bỏ qua', 'Skipped'),
      ),
      MessageCardPlanStatus.todo => (
        Icons.radio_button_unchecked_rounded,
        WebTuiColors.textMuted,
        tr('Chưa làm', 'To do'),
      ),
    };
    final details = [
      label,
      if (step.owner != null) step.owner!,
      if (step.due != null)
        tr(
          'Hạn ${formatCardDay(step.due!)}',
          'Due ${formatCardDay(step.due!)}',
        ),
    ].join(' · ');
    return Semantics(
      label: '${step.title}, $details',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: WebTuiSpacing.xxs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(width: WebTuiSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    step.title,
                    style: WebTuiTypography.bodySmall.copyWith(
                      color: step.status == MessageCardPlanStatus.skipped
                          ? WebTuiColors.textMuted
                          : WebTuiColors.textPrimary,
                      fontWeight: FontWeight.w700,
                      decoration: step.status == MessageCardPlanStatus.skipped
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                  Text(
                    details,
                    style: WebTuiTypography.labelSmall.copyWith(
                      color: WebTuiColors.textSecondary,
                    ),
                  ),
                  if (step.note != null)
                    Text(
                      step.note!,
                      style: WebTuiTypography.labelSmall.copyWith(
                        color: WebTuiColors.textMuted,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

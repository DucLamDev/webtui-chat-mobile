import 'package:flutter/material.dart';

import '../../../../../design_system/tokens/webtui_colors.dart';
import '../../../../../design_system/tokens/webtui_radii.dart';
import '../../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../../design_system/tokens/webtui_typography.dart';
import '../../../../../l10n/app_strings.dart';
import 'ide_ai_json.dart';

/// Dải thông báo ở đầu danh sách tin: chỉ xem, kết nối lại, kẹt + gợi ý.
class IdeAiBanner extends StatelessWidget {
  const IdeAiBanner({
    required this.icon,
    required this.text,
    this.action,
    this.onAction,
    this.tone,
    super.key,
  });

  final IconData icon;
  final String text;
  final String? action;
  final VoidCallback? onAction;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final color = tone ?? WebTuiColors.textSecondary;
    return Container(
      constraints: const BoxConstraints(minHeight: 44),
      margin: const EdgeInsets.fromLTRB(
        WebTuiSpacing.md,
        WebTuiSpacing.xs,
        WebTuiSpacing.md,
        0,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: WebTuiSpacing.md,
        vertical: WebTuiSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: WebTuiColors.backgroundMuted,
        border: Border.all(color: WebTuiColors.border),
        borderRadius: BorderRadius.circular(WebTuiRadii.md),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: WebTuiSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: WebTuiTypography.bodySmall.copyWith(
                color: WebTuiColors.textPrimary,
              ),
            ),
          ),
          if (action != null)
            TextButton(
              style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
              onPressed: onAction,
              child: Text(action!),
            ),
        ],
      ),
    );
  }
}

/// Bảng các bước (kế hoạch AI) ghim phía trên, thu / mở.
class IdeAiPlanPanel extends StatefulWidget {
  const IdeAiPlanPanel({required this.plan, super.key});

  final Object? plan;

  @override
  State<IdeAiPlanPanel> createState() => _IdeAiPlanPanelState();
}

class _IdeAiPlanPanelState extends State<IdeAiPlanPanel> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final rows = aiList(widget.plan);
    if (rows.isEmpty) return const SizedBox.shrink();
    final done = rows.where((r) => aiStr(r['status']) == 'completed').length;
    Map<String, Object?>? current;
    for (final r in rows) {
      if (aiStr(r['status']) == 'in_progress' ||
          aiStr(r['status']) == 'inProgress') {
        current = r;
        break;
      }
    }
    final title = current == null
        ? tr('Các bước', 'Steps')
        : (aiStr(current['active']).isEmpty
              ? aiStr(current['step'])
              : aiStr(current['active']));
    return Container(
      key: const Key('ide_ai_plan_panel'),
      margin: const EdgeInsets.fromLTRB(
        WebTuiSpacing.md,
        WebTuiSpacing.xs,
        WebTuiSpacing.md,
        0,
      ),
      decoration: BoxDecoration(
        color: WebTuiColors.surface,
        border: Border.all(color: WebTuiColors.border),
        borderRadius: BorderRadius.circular(WebTuiRadii.md),
      ),
      child: Column(
        children: [
          InkWell(
            key: const Key('ide_ai_plan_toggle'),
            borderRadius: BorderRadius.circular(WebTuiRadii.md),
            onTap: () => setState(() => _open = !_open),
            child: Container(
              constraints: const BoxConstraints(minHeight: 44),
              padding: const EdgeInsets.symmetric(horizontal: WebTuiSpacing.md),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: WebTuiTypography.bodyMedium.copyWith(
                        color: WebTuiColors.textPrimary,
                      ),
                    ),
                  ),
                  Text(
                    '$done/${rows.length}',
                    style: WebTuiTypography.labelSmall.copyWith(
                      color: WebTuiColors.textMuted,
                    ),
                  ),
                  Icon(
                    _open
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: WebTuiColors.textMuted,
                  ),
                ],
              ),
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                WebTuiSpacing.md,
                0,
                WebTuiSpacing.md,
                WebTuiSpacing.sm,
              ),
              child: Column(
                children: [
                  for (final r in rows)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            switch (aiStr(r['status'])) {
                              'completed' => Icons.check_circle_rounded,
                              'in_progress' ||
                              'inProgress' => Icons.play_circle_rounded,
                              _ => Icons.radio_button_unchecked_rounded,
                            },
                            size: 18,
                            color: aiStr(r['status']) == 'completed'
                                ? WebTuiColors.accentGreen
                                : WebTuiColors.textMuted,
                          ),
                          const SizedBox(width: WebTuiSpacing.sm),
                          Expanded(
                            child: Text(
                              aiStr(r['step']),
                              style: WebTuiTypography.bodySmall.copyWith(
                                color: WebTuiColors.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Hàng chờ tin: Bỏ / Gửi ngay, "Chạy tiếp" khi hàng chờ tạm dừng.
class IdeAiQueuePanel extends StatelessWidget {
  const IdeAiQueuePanel({
    required this.queue,
    required this.paused,
    required this.canControl,
    required this.onRemove,
    required this.onSendNow,
    required this.onRun,
    super.key,
  });

  final List<Map<String, Object?>> queue;
  final bool paused;
  final bool canControl;
  final ValueChanged<String> onRemove;
  final ValueChanged<String> onSendNow;
  final VoidCallback onRun;

  @override
  Widget build(BuildContext context) {
    if (queue.isEmpty) return const SizedBox.shrink();
    return Container(
      key: const Key('ide_ai_queue_panel'),
      margin: const EdgeInsets.fromLTRB(
        WebTuiSpacing.md,
        WebTuiSpacing.xs,
        WebTuiSpacing.md,
        0,
      ),
      padding: const EdgeInsets.all(WebTuiSpacing.sm),
      decoration: BoxDecoration(
        color: WebTuiColors.surface,
        border: Border.all(color: WebTuiColors.border),
        borderRadius: BorderRadius.circular(WebTuiRadii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  tr('Hàng chờ (${queue.length})', 'Queue (${queue.length})'),
                  style: WebTuiTypography.labelSmall.copyWith(
                    color: WebTuiColors.textMuted,
                  ),
                ),
              ),
              if (paused && canControl)
                TextButton(
                  key: const Key('ide_ai_queue_run'),
                  style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
                  onPressed: onRun,
                  child: Text(tr('Chạy tiếp', 'Resume')),
                ),
            ],
          ),
          for (final q in queue)
            Row(
              children: [
                Expanded(
                  child: Text(
                    aiStr(q['text']),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: WebTuiTypography.bodySmall.copyWith(
                      color: WebTuiColors.textPrimary,
                    ),
                  ),
                ),
                if (canControl) ...[
                  TextButton(
                    style: TextButton.styleFrom(
                      minimumSize: const Size(44, 44),
                    ),
                    onPressed: () => onSendNow(aiStr(q['id'])),
                    child: Text(tr('Gửi ngay', 'Send now')),
                  ),
                  IconButton(
                    tooltip: tr('Bỏ', 'Remove'),
                    constraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 44,
                    ),
                    onPressed: () => onRemove(aiStr(q['id'])),
                    icon: const Icon(Icons.close_rounded, size: 18),
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

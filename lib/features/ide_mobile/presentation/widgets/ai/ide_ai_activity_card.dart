import 'package:flutter/material.dart';

import '../../../../../design_system/tokens/webtui_colors.dart';
import '../../../../../design_system/tokens/webtui_radii.dart';
import '../../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../../design_system/tokens/webtui_typography.dart';
import '../../../../../l10n/app_strings.dart';
import 'ide_ai_json.dart';

IconData ideActivityIcon(String kind) => switch (kind) {
  'cmd' => Icons.terminal_rounded,
  'edit' => Icons.edit_note_rounded,
  'read' => Icons.description_outlined,
  'search' => Icons.search_rounded,
  'web' => Icons.public_rounded,
  'agent' => Icons.smart_toy_outlined,
  'plan' => Icons.checklist_rounded,
  _ => Icons.build_circle_outlined,
};

/// Thẻ thao tác thu gọn: một dòng (biểu tượng theo loại, tiêu đề, trạng thái,
/// +/− dòng); chạm mở lệnh / kết quả.
class IdeAiActivityCard extends StatefulWidget {
  const IdeAiActivityCard({required this.item, super.key});

  final Map<String, Object?> item;

  @override
  State<IdeAiActivityCard> createState() => _IdeAiActivityCardState();
}

class _IdeAiActivityCardState extends State<IdeAiActivityCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final kind = aiStr(item['kind']);
    final label = aiStr(item['label']);
    final title = label.isNotEmpty ? label : aiStr(item['title']);
    final status = aiStr(item['status']);
    final add = aiInt(item['add']);
    final del = aiInt(item['del']);
    final cmd = aiStr(item['cmd']);
    final text = aiStr(item['text']);
    final failed = status == 'failed';
    return Container(
      margin: const EdgeInsets.symmetric(vertical: WebTuiSpacing.xxs),
      decoration: BoxDecoration(
        color: WebTuiColors.surface,
        border: Border.all(
          color: failed
              ? WebTuiColors.danger.withValues(alpha: 0.5)
              : WebTuiColors.border,
        ),
        borderRadius: BorderRadius.circular(WebTuiRadii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            key: const Key('ide_ai_activity_toggle'),
            borderRadius: BorderRadius.circular(WebTuiRadii.md),
            onTap: () => setState(() => _open = !_open),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: WebTuiSpacing.md,
                  vertical: WebTuiSpacing.sm,
                ),
                child: Row(
                  children: [
                    Icon(
                      ideActivityIcon(kind),
                      size: 18,
                      color: WebTuiColors.textSecondary,
                    ),
                    const SizedBox(width: WebTuiSpacing.sm),
                    Expanded(
                      child: Text(
                        title.isEmpty ? tr('Thao tác', 'Action') : title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: WebTuiTypography.bodyMedium.copyWith(
                          color: WebTuiColors.textPrimary,
                        ),
                      ),
                    ),
                    if (add > 0)
                      Padding(
                        padding: const EdgeInsets.only(left: WebTuiSpacing.sm),
                        child: Text(
                          '+$add',
                          style: WebTuiTypography.labelSmall.copyWith(
                            color: WebTuiColors.accentGreen,
                          ),
                        ),
                      ),
                    if (del > 0)
                      Padding(
                        padding: const EdgeInsets.only(left: WebTuiSpacing.xs),
                        child: Text(
                          '−$del',
                          style: WebTuiTypography.labelSmall.copyWith(
                            color: WebTuiColors.danger,
                          ),
                        ),
                      ),
                    const SizedBox(width: WebTuiSpacing.sm),
                    _StatusIcon(status: status),
                    Icon(
                      _open
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      size: 20,
                      color: WebTuiColors.textMuted,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                WebTuiSpacing.md,
                0,
                WebTuiSpacing.md,
                WebTuiSpacing.md,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260),
                child: SingleChildScrollView(
                  child: SelectableText(
                    [
                      if (cmd.isNotEmpty) '\$ $cmd',
                      if (text.isNotEmpty) text,
                      if (cmd.isEmpty && text.isEmpty)
                        tr('(chưa có chi tiết)', '(no details yet)'),
                    ].join('\n\n'),
                    style: WebTuiTypography.bodySmall.copyWith(
                      fontFamily: 'monospace',
                      color: WebTuiColors.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StatusIcon extends StatelessWidget {
  const _StatusIcon({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case 'completed':
        return Icon(
          Icons.check_circle_rounded,
          size: 18,
          color: WebTuiColors.accentGreen,
        );
      case 'failed':
        return Icon(Icons.error_rounded, size: 18, color: WebTuiColors.danger);
      case 'declined':
        return Icon(
          Icons.block_rounded,
          size: 18,
          color: WebTuiColors.textMuted,
        );
      default:
        return SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: WebTuiColors.primary,
          ),
        );
    }
  }
}

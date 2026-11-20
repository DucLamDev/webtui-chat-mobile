import 'package:flutter/material.dart';

import '../../../../../design_system/tokens/webtui_radii.dart';
import '../../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../../design_system/tokens/webtui_typography.dart';
import '../../../../../l10n/app_strings.dart';
import '../ide_wb.dart';
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
    final color = tone ?? IdeWb.text;
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
        color: IdeWb.chip,
        border: Border.all(color: IdeWb.border),
        borderRadius: BorderRadius.circular(WebTuiRadii.md),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: WebTuiSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: IdeType.bodySmall.copyWith(color: IdeWb.textStrong),
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
    final all = done == rows.length;
    final small = WebTuiTypography.labelSmall.copyWith(
      fontSize: 12.5,
      fontWeight: FontWeight.w400,
      color: IdeWb.text2,
    );
    // Như thanh "Các bước" của IDE web: một dòng thu gọn nằm trong thẻ ô nhập
    // (viền dưới), mở ra là danh sách tick cuộn được.
    return DecoratedBox(
      key: const Key('ide_ai_plan_panel'),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: IdeWb.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            key: const Key('ide_ai_plan_toggle'),
            onTap: () => setState(() => _open = !_open),
            child: Container(
              constraints: const BoxConstraints(minHeight: 40),
              padding: const EdgeInsets.symmetric(horizontal: WebTuiSpacing.md),
              child: Row(
                children: [
                  Icon(
                    all ? Icons.check_rounded : Icons.checklist_rounded,
                    size: 16,
                    color: all ? IdeWb.ok : IdeWb.text2,
                  ),
                  const SizedBox(width: WebTuiSpacing.sm),
                  Text(
                    tr('Các bước', 'Steps'),
                    style: small.copyWith(
                      fontWeight: FontWeight.w600,
                      color: IdeWb.text,
                    ),
                  ),
                  const SizedBox(width: WebTuiSpacing.sm),
                  Text(
                    '$done/${rows.length}',
                    style: small.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(width: WebTuiSpacing.sm),
                  Expanded(
                    child: Text(
                      all
                          ? tr(
                              'Đã xong cả ${rows.length} bước',
                              'All ${rows.length} steps done',
                            )
                          : (current == null ? '' : title),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: small,
                    ),
                  ),
                  AnimatedRotation(
                    turns: _open ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.expand_more_rounded,
                      size: 18,
                      color: IdeWb.text2,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_open)
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.35,
              ),
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(
                  WebTuiSpacing.md,
                  0,
                  WebTuiSpacing.md,
                  WebTuiSpacing.sm,
                ),
                children: [for (final r in rows) _step(r, small)],
              ),
            ),
        ],
      ),
    );
  }

  Widget _step(Map<String, Object?> r, TextStyle small) {
    final st = aiStr(r['status']);
    final isDone = st == 'completed';
    final now = st == 'in_progress' || st == 'inProgress';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 16,
            height: 18,
            child: Center(
              child: isDone
                  ? Icon(Icons.check_rounded, size: 16, color: IdeWb.ok)
                  : Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          width: 1.5,
                          color: now ? IdeWb.accentInk : IdeWb.text2,
                        ),
                      ),
                    ),
            ),
          ),
          const SizedBox(width: WebTuiSpacing.sm),
          Expanded(
            child: Text(
              aiStr(r['step']),
              style: small.copyWith(
                height: 1.35,
                color: isDone ? IdeWb.text2 : IdeWb.text,
                fontWeight: now ? FontWeight.w600 : FontWeight.w400,
              ),
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
        color: IdeWb.bg,
        border: Border.all(color: IdeWb.border),
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
                    color: IdeWb.text2,
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
                    style: IdeType.bodySmall.copyWith(color: IdeWb.textStrong),
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

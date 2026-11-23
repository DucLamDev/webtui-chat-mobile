import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../../design_system/tokens/webtui_typography.dart';
import '../../../../../l10n/app_strings.dart';
import '../ide_wb.dart';
import 'ide_ai_json.dart';

/// Token của lượt vừa xong, theo đúng cách IDE web tính: Codex có
/// `total.totalTokens`; Claude = vào + ra + tạo bộ nhớ đệm (không tính phần đọc
/// lại từ bộ nhớ đệm).
int? ideAiTurnTokens(Map<String, Object?> usage) {
  final total = aiMap(usage['total'])['totalTokens'];
  if (total is num) return total.round();
  final input = usage['input'];
  if (usage['total'] == null && input is num) {
    final out = usage['output'];
    final created = usage['created'];
    return (input + (out is num ? out : 0) + (created is num ? created : 0))
        .round();
  }
  return null;
}

/// % cửa sổ ngữ cảnh đã dùng (null khi chưa biết cửa sổ của model).
int? ideAiContextPercent(Map<String, Object?> context) {
  final used = context['used'];
  final window = context['window'];
  if (used is num && window is num && used > 0 && window > 0) {
    return (used * 100 / window).round().clamp(0, 100);
  }
  final pct = context['percent'] ?? context['pct'];
  return pct is num ? pct.round().clamp(0, 100) : null;
}

/// Số token gọn: 950, 12,4K, 1,2M (dấu thập phân theo ngôn ngữ).
String ideTokenShort(int n) {
  String one(double v) {
    final s = v >= 100 ? v.round().toString() : v.toStringAsFixed(1);
    final t = s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
    return tr(t.replaceAll('.', ','), t);
  }

  if (n < 1000) return '$n';
  if (n < 1000000) return '${one(n / 1000)}K';
  return '${one(n / 1000000)}M';
}

/// Tên ngắn của chế độ quyền, giống chip chế độ trên IDE web.
String ideAiModeLabel(String mode, {bool team = false}) => switch (mode) {
  'ask' => tr('Hỏi trước', 'Ask first'),
  'edits' => tr('Tự sửa tệp', 'Auto edits'),
  'custom' => tr('Tuỳ chỉnh', 'Custom'),
  'plan' when team => tr('Đội AI', 'AI team'),
  'plan' => tr('Lập kế hoạch', 'Plan'),
  'auto' => tr('Tự làm (không hỏi)', 'Auto (no asking)'),
  'all' => tr('Cho phép hết', 'Allow all'),
  _ => tr('Hỏi trước', 'Ask first'),
};

/// Hàng trạng thái đầu thẻ ô nhập (như `.chat-workbar` của IDE web):
/// "Đang xử lý… 1:23" khi AI chạy, "✓ Đã làm 24:53 · 369,5K token" khi xong.
/// Chưa có lượt nào thì ẩn.
class IdeAiWorkbar extends StatefulWidget {
  const IdeAiWorkbar({
    required this.busy,
    required this.waiting,
    this.startedAt,
    this.finishedAt,
    this.tokens,
    this.trailing,
    super.key,
  });

  final bool busy;

  /// Đang chờ người dùng duyệt.
  final bool waiting;

  /// Giây Unix.
  final num? startedAt;
  final num? finishedAt;
  final int? tokens;
  final Widget? trailing;

  @override
  State<IdeAiWorkbar> createState() => _IdeAiWorkbarState();
}

class _IdeAiWorkbarState extends State<IdeAiWorkbar> {
  Timer? _tick;
  DateTime? _observed;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(IdeAiWorkbar old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (widget.busy) {
      _observed ??= DateTime.now();
      _tick ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else {
      _tick?.cancel();
      _tick = null;
      if (widget.startedAt != null) _observed = null;
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final busy = widget.busy;
    final startMs = widget.startedAt != null
        ? (widget.startedAt! * 1000).round()
        : _observed?.millisecondsSinceEpoch;
    if (!busy && startMs == null) return const SizedBox.shrink();
    final endMs = busy
        ? DateTime.now().millisecondsSinceEpoch
        : widget.finishedAt != null
        ? (widget.finishedAt! * 1000).round()
        : startMs!;
    final secs = ((endMs - (startMs ?? endMs)) / 1000).floor().clamp(
      0,
      1 << 30,
    );
    final time = '${secs ~/ 60}:${(secs % 60).toString().padLeft(2, '0')}';
    final label = busy
        ? (widget.waiting
              ? tr('Chờ bạn xác nhận', 'Waiting for you')
              : tr('Đang xử lý…', 'Working…'))
        : tr('Đã làm', 'Done');
    final style = WebTuiTypography.labelSmall.copyWith(
      fontSize: 12.5,
      fontWeight: FontWeight.w500,
      color: IdeWb.text2,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final tokens = widget.tokens;
    return Container(
      key: const Key('ide_ai_workbar'),
      constraints: const BoxConstraints(minHeight: 32),
      padding: const EdgeInsets.symmetric(horizontal: WebTuiSpacing.md),
      decoration: BoxDecoration(
        color: IdeWb.chip,
        border: Border(bottom: BorderSide(color: IdeWb.border)),
      ),
      child: Row(
        children: [
          // Biểu tượng tĩnh (không vòng quay vô hạn): đồng hồ chạy giây đã cho
          // thấy AI đang làm, đỡ tốn pin khi phiên chạy lâu.
          if (busy)
            Icon(
              widget.waiting
                  ? Icons.pan_tool_alt_outlined
                  : Icons.autorenew_rounded,
              size: 16,
              color: widget.waiting ? IdeWb.warn : IdeWb.accentInk,
            )
          else
            Icon(Icons.check_rounded, size: 16, color: IdeWb.ok),
          const SizedBox(width: WebTuiSpacing.sm),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style.copyWith(color: IdeWb.text),
            ),
          ),
          const SizedBox(width: WebTuiSpacing.md),
          Icon(Icons.timer_outlined, size: 14, color: IdeWb.text2),
          const SizedBox(width: 3),
          Text(time, style: style),
          if (!busy && tokens != null) ...[
            const SizedBox(width: WebTuiSpacing.md),
            Flexible(
              child: Text(
                tr(
                  '${ideTokenShort(tokens)} token',
                  '${ideTokenShort(tokens)} tokens',
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style,
              ),
            ),
          ],
          const Spacer(),
          ?widget.trailing,
        ],
      ),
    );
  }
}

/// Chip ở hàng dưới thẻ ô nhập: mô hình, ngữ cảnh, chế độ.
class IdeAiChip extends StatelessWidget {
  const IdeAiChip({
    required this.label,
    required this.onTap,
    this.icon,
    this.accent = false,
    this.semantics,
    this.leading,
    super.key,
  });

  final String label;
  final IconData? icon;
  final Widget? leading;
  final bool accent;
  final String? semantics;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final fg = accent ? IdeWb.accentInk : IdeWb.text;
    return Semantics(
      button: true,
      label: semantics,
      excludeSemantics: semantics != null,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: ConstrainedBox(
          // Chip cao 30 nhìn gọn; vùng bấm thật 44 nhờ Padding dọc.
          constraints: const BoxConstraints(minHeight: 44),
          child: Center(
            child: Container(
              height: 30,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: accent ? IdeWb.accentSoft : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: accent ? null : Border.all(color: IdeWb.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ?leading,
                  if (icon != null) ...[
                    Icon(icon, size: 15, color: fg),
                    const SizedBox(width: 5),
                  ],
                  Text(
                    label,
                    maxLines: 1,
                    style: WebTuiTypography.labelSmall.copyWith(
                      fontSize: 12.5,
                      fontWeight: accent ? FontWeight.w600 : FontWeight.w500,
                      color: fg,
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
}

/// Vạch ngữ cảnh nhỏ (xanh < 70%, cam < 90%, đỏ từ 90%) đặt trong chip.
class IdeAiContextBar extends StatelessWidget {
  const IdeAiContextBar({required this.percent, super.key});

  final int percent;

  @override
  Widget build(BuildContext context) {
    final color = percent >= 90
        ? IdeWb.danger
        : percent >= 70
        ? IdeWb.warn
        : IdeWb.ok;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Container(
        width: 22,
        height: 5,
        decoration: BoxDecoration(
          color: IdeWb.border,
          borderRadius: BorderRadius.circular(3),
        ),
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: percent / 100,
          child: Container(
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
      ),
    );
  }
}

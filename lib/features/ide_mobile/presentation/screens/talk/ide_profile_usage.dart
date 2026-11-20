import 'package:flutter/material.dart';

import '../../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../../design_system/tokens/webtui_typography.dart';
import '../../../../../l10n/app_strings.dart';
import '../../../domain/ide_more_time.dart';
import '../../../domain/ide_profile_models.dart';
import '../../../domain/ide_visible_text.dart';
import '../../widgets/ide_wb.dart';
import '../../widgets/markdown/ide_blocks_model.dart';
import '../../widgets/markdown/ide_chart_view.dart';
import '../more/ide_more_common.dart';
import 'ide_profile_widgets.dart';

/// Biểu đồ theo ngày (`profile.usage_daily`) hoặc theo model khi không có.
IdeChartSpec? ideProfileChartSpec({
  required List<IdeUsageDay>? daily,
  required List<IdeUsageRow> byModel,
}) {
  if (daily != null) {
    final vals = [for (final d in daily) d.cost];
    if (vals.every((v) => v == null)) return null;
    return IdeChartSpec(
      type: daily.length > 31 ? IdeChartType.line : IdeChartType.bar,
      labels: [for (final d in daily) d.day.substring(5)],
      series: [IdeChartSeries(tr('Chi phí', 'Cost'), vals)],
      title: tr('Chi phí AI theo ngày', 'AI cost per day'),
      unit: 'USD',
    );
  }
  final rows = [
    for (final r in byModel)
      if (r.cost != null) r,
  ];
  if (rows.isEmpty) return null;
  return IdeChartSpec(
    type: IdeChartType.bar,
    labels: [for (final r in rows) ideVisibleText(r.label)],
    series: [
      IdeChartSeries(tr('Chi phí', 'Cost'), [for (final r in rows) r.cost]),
    ],
    title: tr('Chi phí AI theo mô hình', 'AI cost per model'),
    unit: 'USD',
  );
}

class IdeUsageTotals extends StatelessWidget {
  const IdeUsageTotals({required this.profile, super.key});

  final IdeProfile profile;

  @override
  Widget build(BuildContext context) {
    final t = profile.totals;
    if (t == null) {
      return Text(
        tr('Chưa có số liệu dùng AI.', 'No AI usage yet.'),
        style: IdeType.bodySmall.copyWith(color: IdeWb.text),
      );
    }
    return Column(
      children: [
        IdeKeyValue(tr('Lượt hỏi', 'Requests'), ideFormatCount(t.requests)),
        IdeKeyValue(tr('Token vào', 'Input tokens'), ideFormatCount(t.input)),
        IdeKeyValue(tr('Token ra', 'Output tokens'), ideFormatCount(t.output)),
        IdeKeyValue(
          tr('Đọc bộ nhớ đệm', 'Cache read'),
          ideFormatCount(t.cacheRead),
        ),
        IdeKeyValue(
          tr('Ghi bộ nhớ đệm', 'Cache write'),
          ideFormatCount(t.cacheWrite),
        ),
        IdeKeyValue(
          tr('Chi phí quy đổi', 'Converted cost'),
          ideFormatUsd(t.cost),
        ),
        if (profile.rateVnd != null && t.cost != null)
          IdeKeyValue(
            tr('Ước tính (VND)', 'Estimate (VND)'),
            '${ideFormatCount(profile.rateVnd! * t.cost!)} đ',
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.only(top: WebTuiSpacing.xs),
            child: Text(
              tr(
                'Giá quy đổi theo giá API công khai.',
                'Converted at public API prices.',
              ),
              style: WebTuiTypography.labelSmall.copyWith(color: IdeWb.text2),
            ),
          ),
        ),
      ],
    );
  }
}

class IdeUsageRows extends StatelessWidget {
  const IdeUsageRows({required this.rows, super.key});

  final List<IdeUsageRow> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return Text(
        tr('Chưa có dữ liệu.', 'No data.'),
        style: IdeType.bodySmall.copyWith(color: IdeWb.text),
      );
    }
    return Column(
      children: [
        for (final r in rows)
          IdeKeyValue(
            ideVisibleText(r.label.isEmpty ? r.tool : r.label),
            '${ideFormatUsd(r.cost)} · ${ideFormatCount(r.input)} / ${ideFormatCount(r.output)}',
          ),
      ],
    );
  }
}

class IdeAiUsageView extends StatelessWidget {
  const IdeAiUsageView({required this.usage, super.key});

  final IdeAiUsage usage;

  @override
  Widget build(BuildContext context) {
    Widget acc(String name, IdeAiAccount a) => a.isEmpty
        ? const SizedBox.shrink()
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IdeKeyValue(
                name,
                ideVisibleText(a.label.isEmpty ? a.id : a.label),
              ),
              if (a.note.isNotEmpty)
                Text(
                  ideVisibleText(a.note),
                  style: WebTuiTypography.labelSmall.copyWith(
                    color: IdeWb.text2,
                  ),
                ),
            ],
          );
    final nothing =
        usage.claude.isEmpty && usage.codex.isEmpty && usage.granted.isEmpty;
    if (nothing) {
      return Text(
        tr('Chưa được cấp tài khoản AI.', 'No AI account granted.'),
        style: IdeType.bodySmall.copyWith(color: IdeWb.text),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        acc('Claude', usage.claude),
        acc('Codex', usage.codex),
        for (final g in usage.granted)
          IdeKeyValue(
            ideVisibleText('${g.tool} ${g.mode}'.trim()),
            ideVisibleText(g.label),
          ),
      ],
    );
  }
}

class IdeAiRoutesView extends StatelessWidget {
  const IdeAiRoutesView({required this.routes, super.key});

  final List<IdeAiRoute> routes;

  @override
  Widget build(BuildContext context) {
    if (routes.isEmpty) {
      return Text(
        tr('Chưa có tài khoản nào.', 'No accounts.'),
        style: IdeType.bodySmall.copyWith(color: IdeWb.text),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final r in routes)
          Padding(
            padding: const EdgeInsets.only(bottom: WebTuiSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: WebTuiSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      ideVisibleText(r.label.isEmpty ? r.id : r.label),
                      style: IdeType.bodyMedium.copyWith(
                        color: IdeWb.textStrong,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (r.state.isNotEmpty) IdeTag(ideVisibleText(r.state)),
                    if (r.blocked)
                      IdeTag(tr('Bị chặn', 'Blocked'), color: IdeWb.danger),
                  ],
                ),
                for (final w in r.windows) _QuotaBar(w: w),
              ],
            ),
          ),
      ],
    );
  }
}

class _QuotaBar extends StatelessWidget {
  const _QuotaBar({required this.w});

  final IdeQuotaWindow w;

  @override
  Widget build(BuildContext context) {
    final used = w.used;
    final label = ideVisibleText(w.label.isEmpty ? w.name : w.label);
    final reset = w.resetsAt == null
        ? ''
        : ' · ${tr('đặt lại', 'resets')} ${ideFormatDateTime(w.resetsAt!)}';
    return Padding(
      padding: const EdgeInsets.only(top: WebTuiSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label: ${used == null ? '—' : '${used.round()}%'}$reset',
            style: WebTuiTypography.labelSmall.copyWith(color: IdeWb.text),
          ),
          LinearProgressIndicator(
            value: used == null ? 0 : used / 100,
            minHeight: 6,
          ),
        ],
      ),
    );
  }
}

/// Biểu đồ hoặc "chưa có dữ liệu".
class IdeProfileChart extends StatelessWidget {
  const IdeProfileChart({required this.spec, super.key});

  final IdeChartSpec? spec;

  @override
  Widget build(BuildContext context) => spec == null
      ? Text(
          tr('Chưa có dữ liệu để vẽ biểu đồ.', 'No data to chart.'),
          style: IdeType.bodySmall.copyWith(color: IdeWb.text),
        )
      : IdeChartView(spec: spec!);
}

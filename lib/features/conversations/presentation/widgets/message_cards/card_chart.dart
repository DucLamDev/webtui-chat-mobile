import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../../design_system/tokens/webtui_colors.dart';
import '../../../../../design_system/tokens/webtui_radii.dart';
import '../../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../../design_system/tokens/webtui_typography.dart';
import '../../../application/use_cases/message_card_form_validator.dart';
import '../../../domain/entities/message_card.dart';
import 'card_common.dart';
import 'card_table.dart';

/// Biểu đồ cột / đường / tròn của thẻ, vẽ bằng [CustomPainter] (không thêm gói).
///
/// Chạm vào biểu đồ để xem số liệu của một nhóm; "Xem số liệu" mở bảng đầy đủ
/// (cho người không phân biệt được màu / dùng trình đọc màn hình).
class MessageCardChartView extends StatefulWidget {
  const MessageCardChartView({required this.chart, super.key});

  final MessageCardChart chart;

  @override
  State<MessageCardChartView> createState() => _MessageCardChartViewState();
}

class _MessageCardChartViewState extends State<MessageCardChartView> {
  int? _selected;
  bool _showTable = false;

  @override
  void didUpdateWidget(covariant MessageCardChartView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.chart, widget.chart)) _selected = null;
  }

  @override
  Widget build(BuildContext context) {
    final chart = widget.chart;
    if (!chart.hasData || chart.categoryCount == 0) {
      return const MessageCardEmptyNote('Chưa có dữ liệu biểu đồ.');
    }
    final isPie = chart.kind == MessageCardChartKind.pie;
    final textStyle = WebTuiTypography.labelSmall.copyWith(
      color: WebTuiColors.textMuted,
      fontSize: 10,
    );
    final selection = _selected == null ? null : _selectionText(_selected!);
    return Semantics(
      container: true,
      label: _semanticLabel(chart),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (chart.unit != null)
            Padding(
              padding: const EdgeInsets.only(bottom: WebTuiSpacing.xs),
              child: Text(
                'Đơn vị: ${chart.unit}',
                style: WebTuiTypography.labelSmall.copyWith(
                  color: WebTuiColors.textSecondary,
                ),
              ),
            ),
          LayoutBuilder(
            builder: (context, constraints) {
              final available = constraints.maxWidth.isFinite
                  ? constraints.maxWidth
                  : 280.0;
              final height = isPie ? 168.0 : 184.0;
              final minWidth = isPie
                  ? available
                  : _cartesianMinWidth(chart, available);
              final painter = MessageCardChartPainter(
                chart: chart,
                textStyle: textStyle,
                selectedIndex: _selected,
              );
              final canvas = GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (details) {
                  final index = painter.indexAt(
                    details.localPosition,
                    Size(minWidth, height),
                  );
                  setState(() => _selected = index == _selected ? null : index);
                },
                child: CustomPaint(
                  size: Size(minWidth, height),
                  painter: painter,
                ),
              );
              if (minWidth <= available) return canvas;
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: canvas,
              );
            },
          ),
          if (selection != null)
            Padding(
              padding: const EdgeInsets.only(top: WebTuiSpacing.xs),
              child: Text(
                selection,
                style: WebTuiTypography.bodySmall.copyWith(
                  color: WebTuiColors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          _ChartLegend(chart: chart),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: WebTuiSpacing.xs,
                ),
                minimumSize: const Size(44, 36),
              ),
              onPressed: () => setState(() => _showTable = !_showTable),
              icon: Icon(
                _showTable
                    ? Icons.expand_less_rounded
                    : Icons.table_rows_outlined,
                size: 18,
              ),
              label: Text(_showTable ? 'Ẩn số liệu' : 'Xem số liệu'),
            ),
          ),
          if (_showTable) MessageCardTableView(table: chartAsTable(chart)),
        ],
      ),
    );
  }

  String _selectionText(int index) {
    final chart = widget.chart;
    final unit = chart.unit == null ? '' : ' ${chart.unit}';
    if (chart.kind == MessageCardChartKind.pie) {
      final slices = pieSlicesOf(chart);
      if (index < 0 || index >= slices.length) return '';
      final slice = slices[index];
      return '${slice.label}: ${formatMessageCardNumber(slice.value)}$unit'
          ' (${slice.percentLabel})';
    }
    final parts = <String>[
      for (final series in chart.series)
        if (index < series.values.length && series.values[index] != null)
          '${series.name.isEmpty ? 'Giá trị' : series.name}: '
              '${formatMessageCardNumber(series.values[index]!)}$unit',
    ];
    final values = parts.isEmpty ? 'Không có số liệu' : parts.join(' · ');
    return '${chart.labelAt(index)} — $values';
  }
}

String _semanticLabel(MessageCardChart chart) {
  final kind = switch (chart.kind) {
    MessageCardChartKind.bar => 'Biểu đồ cột',
    MessageCardChartKind.line => 'Biểu đồ đường',
    MessageCardChartKind.pie => 'Biểu đồ tròn',
  };
  return '$kind, ${chart.categoryCount} mục, ${chart.series.length} dãy số liệu';
}

double _cartesianMinWidth(MessageCardChart chart, double available) {
  final series = math.max(1, chart.series.length);
  final slot = chart.kind == MessageCardChartKind.bar
      ? 10.0 * series + 14
      : 22.0;
  return math.max(available, 48 + chart.categoryCount * slot);
}

/// Dãy màu phân loại cố định (không xoay vòng, không sinh màu mới): màu đi theo
/// thứ tự dãy số liệu. Thứ tự đã kiểm cho người mù màu (cặp liền kề).
const messageCardSeriesColors = <Color>[
  Color(0xFF2A78D6),
  Color(0xFFEB6834),
  Color(0xFF1BAF7A),
  Color(0xFFEDA100),
  Color(0xFFE87BA4),
  Color(0xFF008300),
  Color(0xFF6250D6),
  Color(0xFFE34948),
];

/// Một miếng của biểu đồ tròn (đã gộp phần nhỏ thành "Khác").
final class MessageCardPieSlice {
  const MessageCardPieSlice({
    required this.label,
    required this.value,
    required this.fraction,
    required this.colorIndex,
    required this.indices,
  });

  final String label;
  final double value;
  final double fraction;
  final int colorIndex;

  /// Vị trí gốc trong `labels` (miếng "Khác" có nhiều vị trí).
  final List<int> indices;

  String get percentLabel => '${formatMessageCardNumber(fraction * 100)}%';
}

/// Miếng của biểu đồ tròn: bỏ giá trị trống / âm / bằng 0; quá 8 miếng thì giữ
/// 7 miếng lớn nhất, gộp phần còn lại thành "Khác" (không sinh thêm màu).
List<MessageCardPieSlice> pieSlicesOf(MessageCardChart chart) {
  if (chart.series.isEmpty) return const [];
  final values = chart.series.first.values;
  final entries = <(int, double)>[
    for (var index = 0; index < values.length; index++)
      if (values[index] case final value? when value > 0) (index, value),
  ];
  final total = entries.fold<double>(0, (sum, entry) => sum + entry.$2);
  if (total <= 0) return const [];
  final maxSlices = messageCardSeriesColors.length;
  var kept = entries;
  List<(int, double)> rest = const [];
  if (entries.length > maxSlices) {
    final sorted = [...entries]..sort((a, b) => b.$2.compareTo(a.$2));
    final keptIndices = sorted.take(maxSlices - 1).map((e) => e.$1).toSet();
    kept = entries.where((e) => keptIndices.contains(e.$1)).toList();
    rest = entries.where((e) => !keptIndices.contains(e.$1)).toList();
  }
  return [
    for (var slot = 0; slot < kept.length; slot++)
      MessageCardPieSlice(
        label: chart.labelAt(kept[slot].$1),
        value: kept[slot].$2,
        fraction: kept[slot].$2 / total,
        colorIndex: slot,
        indices: [kept[slot].$1],
      ),
    if (rest.isNotEmpty)
      MessageCardPieSlice(
        label: 'Khác',
        value: rest.fold<double>(0, (sum, entry) => sum + entry.$2),
        fraction: rest.fold<double>(0, (sum, entry) => sum + entry.$2) / total,
        colorIndex: maxSlices - 1,
        indices: [for (final entry in rest) entry.$1],
      ),
  ];
}

/// Số liệu biểu đồ dạng bảng (cột đầu là nhãn, mỗi dãy một cột).
MessageCardTable chartAsTable(MessageCardChart chart) {
  final count = math.min(chart.categoryCount, messageCardMaxChartPoints);
  final unit = chart.unit == null ? '' : ' (${chart.unit})';
  return MessageCardTable(
    columns: [
      'Mục',
      for (final series in chart.series)
        '${series.name.isEmpty ? 'Giá trị' : series.name}$unit',
    ],
    rows: [
      for (var index = 0; index < count; index++)
        [
          chart.labelAt(index),
          for (final series in chart.series)
            index < series.values.length && series.values[index] != null
                ? formatMessageCardNumber(series.values[index]!)
                : '–',
        ],
    ],
  );
}

class _ChartLegend extends StatelessWidget {
  const _ChartLegend({required this.chart});

  final MessageCardChart chart;

  @override
  Widget build(BuildContext context) {
    final entries = chart.kind == MessageCardChartKind.pie
        ? [
            for (final slice in pieSlicesOf(chart))
              (
                messageCardSeriesColors[slice.colorIndex],
                '${slice.label} · ${slice.percentLabel}',
              ),
          ]
        : chart.series.length < 2
        ? const <(Color, String)>[]
        : [
            for (var index = 0; index < chart.series.length; index++)
              (
                messageCardSeriesColors[index % messageCardSeriesColors.length],
                chart.series[index].name.isEmpty
                    ? 'Dãy ${index + 1}'
                    : chart.series[index].name,
              ),
          ];
    if (entries.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: WebTuiSpacing.sm),
      child: Wrap(
        spacing: WebTuiSpacing.md,
        runSpacing: WebTuiSpacing.xs,
        children: [
          for (final (color, label) in entries)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(WebTuiRadii.xs / 2),
                  ),
                ),
                const SizedBox(width: WebTuiSpacing.xs),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: WebTuiTypography.labelSmall.copyWith(
                      color: WebTuiColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Vẽ biểu đồ của thẻ. An toàn với dữ liệu rỗng, số âm, điểm thiếu (`null`):
/// không có điểm nào thì chỉ vẽ trục / khung trống.
class MessageCardChartPainter extends CustomPainter {
  MessageCardChartPainter({
    required this.chart,
    required this.textStyle,
    this.selectedIndex,
  });

  final MessageCardChart chart;
  final TextStyle textStyle;
  final int? selectedIndex;

  static const double _bottomGutter = 22;
  static const double _topPadding = 8;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    if (chart.kind == MessageCardChartKind.pie) {
      _paintPie(canvas, size);
    } else {
      _paintCartesian(canvas, size);
    }
  }

  /// Nhóm (cột / điểm / miếng) dưới vị trí chạm; `null` khi chạm ngoài.
  int? indexAt(Offset position, Size size) {
    if (chart.kind == MessageCardChartKind.pie) {
      final slices = pieSlicesOf(chart);
      if (slices.isEmpty) return null;
      final center = size.center(Offset.zero);
      final radius = _pieRadius(size);
      final offset = position - center;
      if (offset.distance > radius + 6) return null;
      var angle = math.atan2(offset.dy, offset.dx) + math.pi / 2;
      if (angle < 0) angle += 2 * math.pi;
      var start = 0.0;
      for (var index = 0; index < slices.length; index++) {
        final sweep = slices[index].fraction * 2 * math.pi;
        if (angle >= start && angle < start + sweep) return index;
        start += sweep;
      }
      return slices.length - 1;
    }
    final count = chart.categoryCount;
    if (count == 0) return null;
    final plot = _plotRect(size, _scale());
    if (position.dx < plot.left || position.dx > plot.right) return null;
    final slot = plot.width / count;
    return ((position.dx - plot.left) / slot).floor().clamp(0, count - 1);
  }

  // ------------------------------------------------------------ cartesian

  _Scale _scale() {
    var minValue = 0.0;
    var maxValue = 0.0;
    var any = false;
    for (final series in chart.series) {
      for (final value in series.values) {
        if (value == null || !value.isFinite) continue;
        any = true;
        minValue = math.min(minValue, value);
        maxValue = math.max(maxValue, value);
      }
    }
    if (!any || minValue == maxValue) {
      maxValue = minValue + 1;
    }
    final step = _niceStep((maxValue - minValue) / 4);
    final niceMin = (minValue / step).floorToDouble() * step;
    var niceMax = (maxValue / step).ceilToDouble() * step;
    if (!(niceMax > niceMin)) niceMax = niceMin + step;
    // Đếm theo chỉ số (không cộng dồn số thực) để không lặp vô hạn khi số rất lớn.
    final steps = ((niceMax - niceMin) / step).round().clamp(1, 10);
    final ticks = <double>[
      for (var index = 0; index <= steps; index++) niceMin + step * index,
    ];
    return _Scale(min: niceMin, max: niceMax, ticks: ticks);
  }

  Rect _plotRect(Size size, _Scale scale) {
    var gutter = 0.0;
    for (final tick in scale.ticks) {
      gutter = math.max(gutter, _measure(formatMessageCardNumber(tick)).width);
    }
    final left = math.min(gutter + 6, 64.0);
    return Rect.fromLTRB(
      left,
      _topPadding,
      math.max(left + 1, size.width - 4),
      math.max(_topPadding + 1, size.height - _bottomGutter),
    );
  }

  void _paintCartesian(Canvas canvas, Size size) {
    final scale = _scale();
    final plot = _plotRect(size, scale);
    final range = scale.max - scale.min;
    double yOf(double value) {
      // Số cực lớn / khoảng bằng 0: không để ra NaN (Canvas từ chối toạ độ NaN).
      final ratio = range.isFinite && range > 0
          ? (value - scale.min) / range
          : 0.0;
      return plot.bottom -
          (ratio.isFinite ? ratio.clamp(0.0, 1.0) : 0.0) * plot.height;
    }

    final grid = Paint()
      ..color = WebTuiColors.border
      ..strokeWidth = 1;
    for (final tick in scale.ticks) {
      final y = yOf(tick);
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
      final label = _layout(formatMessageCardNumber(tick), plot.left - 6);
      label.paint(
        canvas,
        Offset(plot.left - 6 - label.width, y - label.height / 2),
      );
    }
    final zeroY = yOf(0);
    canvas.drawLine(
      Offset(plot.left, zeroY),
      Offset(plot.right, zeroY),
      Paint()
        ..color = WebTuiColors.textMuted
        ..strokeWidth = 1,
    );

    final count = chart.categoryCount;
    if (count == 0) return;
    final slot = plot.width / count;

    final selected = selectedIndex;
    if (selected != null && selected >= 0 && selected < count) {
      final rect = Rect.fromLTWH(
        plot.left + slot * selected,
        plot.top,
        slot,
        plot.height,
      );
      canvas.drawRect(
        rect,
        Paint()..color = WebTuiColors.primary.withValues(alpha: 0.07),
      );
    }

    // Nhãn trục ngang: bỏ bớt nhãn khi chật để không chồng chữ.
    final labelWidth = math.max(slot - 2, 8.0);
    var every = 1;
    for (var index = 0; index < count; index++) {
      final width = _measure(chart.labelAt(index)).width;
      every = math.max(every, (width / math.max(slot, 1)).ceil());
    }
    every = math.min(every, math.max(1, count));
    for (var index = 0; index < count; index += every) {
      final painter = _layout(chart.labelAt(index), labelWidth * every);
      final x = plot.left + slot * index + slot / 2 - painter.width / 2;
      painter.paint(
        canvas,
        Offset(
          x.clamp(0, math.max(0, size.width - painter.width)).toDouble(),
          plot.bottom + 4,
        ),
      );
    }

    if (chart.kind == MessageCardChartKind.bar) {
      _paintBars(canvas, plot, slot, yOf, zeroY);
    } else {
      _paintLines(canvas, plot, slot, yOf);
    }
  }

  void _paintBars(
    Canvas canvas,
    Rect plot,
    double slot,
    double Function(double) yOf,
    double zeroY,
  ) {
    final seriesCount = math.max(1, chart.series.length);
    final groupWidth = slot * 0.72;
    final gap = seriesCount > 1 ? 2.0 : 0.0;
    final barWidth = math.max(
      1.0,
      (groupWidth - gap * (seriesCount - 1)) / seriesCount,
    );
    final radius = Radius.circular(math.min(4, barWidth / 2));
    for (var s = 0; s < chart.series.length; s++) {
      final paint = Paint()
        ..color = messageCardSeriesColors[s % messageCardSeriesColors.length];
      final values = chart.series[s].values;
      for (var index = 0; index < values.length; index++) {
        final value = values[index];
        if (value == null || !value.isFinite) continue;
        final left =
            plot.left +
            slot * index +
            (slot - groupWidth) / 2 +
            s * (barWidth + gap);
        final y = yOf(value);
        final top = math.min(y, zeroY);
        final bottom = math.max(y, zeroY);
        if (bottom - top < 0.5) continue;
        final rect = Rect.fromLTRB(left, top, left + barWidth, bottom);
        // Đầu cột bo tròn, chân cột bám đường 0.
        canvas.drawRRect(
          value >= 0
              ? RRect.fromRectAndCorners(
                  rect,
                  topLeft: radius,
                  topRight: radius,
                )
              : RRect.fromRectAndCorners(
                  rect,
                  bottomLeft: radius,
                  bottomRight: radius,
                ),
          paint,
        );
      }
    }
  }

  void _paintLines(
    Canvas canvas,
    Rect plot,
    double slot,
    double Function(double) yOf,
  ) {
    final showMarkers = chart.categoryCount <= 40;
    for (var s = 0; s < chart.series.length; s++) {
      final color = messageCardSeriesColors[s % messageCardSeriesColors.length];
      final line = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round;
      final values = chart.series[s].values;
      final path = Path();
      var drawing = false;
      final points = <Offset>[];
      for (var index = 0; index < values.length; index++) {
        final value = values[index];
        if (value == null || !value.isFinite) {
          drawing = false; // điểm thiếu: ngắt đường
          continue;
        }
        final point = Offset(plot.left + slot * index + slot / 2, yOf(value));
        points.add(point);
        if (drawing) {
          path.lineTo(point.dx, point.dy);
        } else {
          path.moveTo(point.dx, point.dy);
          drawing = true;
        }
      }
      canvas.drawPath(path, line);
      final selected = selectedIndex;
      for (var index = 0; index < values.length; index++) {
        final value = values[index];
        if (value == null || !value.isFinite) continue;
        final isSelected = index == selected;
        if (!showMarkers && !isSelected) continue;
        final point = Offset(plot.left + slot * index + slot / 2, yOf(value));
        canvas
          ..drawCircle(point, isSelected ? 6 : 4, Paint()..color = Colors.white)
          ..drawCircle(point, isSelected ? 4.5 : 3, Paint()..color = color);
      }
    }
  }

  // ------------------------------------------------------------------ pie

  double _pieRadius(Size size) =>
      math.max(0, math.min(size.width, size.height) / 2 - 8);

  void _paintPie(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = _pieRadius(size);
    if (radius <= 0) return;
    final slices = pieSlicesOf(chart);
    if (slices.isEmpty) {
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = WebTuiColors.border
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      return;
    }
    var start = -math.pi / 2;
    final separator = Paint()
      ..color = WebTuiColors.surface
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (var index = 0; index < slices.length; index++) {
      final slice = slices[index];
      final sweep = slice.fraction * 2 * math.pi;
      final selected = index == selectedIndex;
      final r = selected ? radius + 5 : radius;
      final rect = Rect.fromCircle(center: center, radius: r);
      canvas.drawArc(
        rect,
        start,
        sweep,
        true,
        Paint()..color = messageCardSeriesColors[slice.colorIndex],
      );
      if (slices.length > 1) {
        canvas.drawArc(rect, start, sweep, true, separator);
      }
      start += sweep;
    }
  }

  // ----------------------------------------------------------------- chữ

  Size _measure(String text) => _layout(text, double.infinity).size;

  TextPainter _layout(String text, double maxWidth) {
    return TextPainter(
      text: TextSpan(text: text, style: textStyle),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(
      maxWidth: maxWidth.isFinite ? math.max(0, maxWidth) : double.infinity,
    );
  }

  @override
  bool shouldRepaint(covariant MessageCardChartPainter oldDelegate) =>
      !identical(oldDelegate.chart, chart) ||
      oldDelegate.selectedIndex != selectedIndex ||
      oldDelegate.textStyle != textStyle;
}

final class _Scale {
  const _Scale({required this.min, required this.max, required this.ticks});

  final double min;
  final double max;
  final List<double> ticks;
}

/// Bước chia trục "đẹp" (1, 2, 2,5, 5 × 10ⁿ).
double _niceStep(double rough) {
  if (!rough.isFinite || rough <= 0) return 1;
  final exponent = (math.log(rough) / math.ln10).floorToDouble();
  final base = math.pow(10, exponent).toDouble();
  if (!base.isFinite || base <= 0) return 1;
  final fraction = rough / base;
  final nice = fraction <= 1
      ? 1.0
      : fraction <= 2
      ? 2.0
      : fraction <= 2.5
      ? 2.5
      : fraction <= 5
      ? 5.0
      : 10.0;
  return nice * base;
}

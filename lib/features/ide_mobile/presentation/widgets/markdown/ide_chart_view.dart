import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../../design_system/tokens/webtui_colors.dart';
import '../../../../../design_system/tokens/webtui_radii.dart';
import '../../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../../l10n/app_strings.dart';
import '../ide_wb.dart';
import 'ide_blocks_model.dart';

/// 8 màu phân loại theo thứ tự cố định (sáng / tối), cùng ý bảng `cb-c0–7` của
/// IDE web; biểu đồ tròn quá 8 phần đã gom vào "Khác".
/// Số điểm tối đa của một chuỗi còn vẽ chấm tròn trên đường.
const ideChartMaxDotPoints = 60;

/// Có vẽ chấm tròn cho chuỗi [points] điểm không (hàm thuần, để test).
bool ideChartShowDots(int points) => points <= ideChartMaxDotPoints;

const _lightPalette = <Color>[
  Color(0xFF0A6CDE),
  Color(0xFFD9822B),
  Color(0xFF21A875),
  Color(0xFF8E54D6),
  Color(0xFFD14B73),
  Color(0xFF1B9BB5),
  Color(0xFF8A8F1E),
  Color(0xFF6B7385),
];
const _darkPalette = <Color>[
  Color(0xFF4C9DFF),
  Color(0xFFEDB04A),
  Color(0xFF2FBF87),
  Color(0xFFB58BF0),
  Color(0xFFF07FA0),
  Color(0xFF4CC3DB),
  Color(0xFFC9CE4F),
  Color(0xFF9AA3B8),
];

/// [dark]: bảng màu của màn đang vẽ (mặc định theo máy).
List<Color> ideChartPalette({bool? dark}) =>
    (dark ?? IdeWbPalette.current.isDark) ? _darkPalette : _lightPalette;

String ideFormatNumber(double? v, String unit) {
  if (v == null) return '–';
  final fixed = v == v.roundToDouble()
      ? v.round().toString()
      : v.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');
  final neg = fixed.startsWith('-');
  final parts = (neg ? fixed.substring(1) : fixed).split('.');
  final grouped = parts.first.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => '.',
  );
  final text =
      '${neg ? '-' : ''}$grouped${parts.length > 1 ? ',${parts[1]}' : ''}';
  return unit.isEmpty ? text : '$text $unit';
}

double _niceMax(double v) {
  if (v <= 0) return 1;
  final p = math.pow(10, (math.log(v) / math.ln10).floor()).toDouble();
  final m = v / p;
  const steps = [1, 1.2, 1.5, 2, 2.5, 3, 4, 5, 6, 8, 10];
  return steps.firstWhere((x) => m <= x + 1e-9) * p;
}

/// Biểu đồ cột / đường / tròn tự vẽ bằng CustomPainter, kèm chú thích và bảng
/// số liệu xem được bằng chữ.
class IdeChartView extends StatefulWidget {
  const IdeChartView({required this.spec, super.key});

  final IdeChartSpec spec;

  @override
  State<IdeChartView> createState() => _IdeChartViewState();
}

class _IdeChartViewState extends State<IdeChartView> {
  bool _showTable = false;

  @override
  Widget build(BuildContext context) {
    final spec = widget.spec.collapsedPie;
    final palette = ideChartPalette(dark: IdeWbPalette.of(context).isDark);
    final pie = spec.type == IdeChartType.pie;
    final legendNames = pie
        ? spec.labels
        : [for (final s in spec.series) s.name];
    final summary = [
      spec.title.isEmpty ? tr('Biểu đồ', 'Chart') : spec.title,
      for (var i = 0; i < spec.labels.length; i++)
        '${spec.labels[i]}: ${[for (final s in spec.series) ideFormatNumber(s.values[i], spec.unit)].join(', ')}',
    ].join('; ');
    return Container(
      margin: const EdgeInsets.symmetric(vertical: WebTuiSpacing.sm),
      padding: const EdgeInsets.all(WebTuiSpacing.md),
      decoration: BoxDecoration(
        color: IdeWbPalette.of(context).bg,
        borderRadius: BorderRadius.circular(WebTuiRadii.md),
        border: Border.all(color: IdeWbPalette.of(context).border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (spec.title.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: WebTuiSpacing.sm),
              child: Text(
                spec.title,
                style: IdeType.titleMedium.copyWith(
                  color: IdeWbPalette.of(context).textStrong,
                ),
              ),
            ),
          Semantics(
            label: summary,
            image: true,
            excludeSemantics: true,
            child: SizedBox(
              height: pie ? 180 : 200,
              width: double.infinity,
              child: CustomPaint(
                painter: pie
                    ? _PiePainter(spec, palette, IdeWbPalette.of(context).bg)
                    : _AxisPainter(
                        spec,
                        palette,
                        grid: IdeWbPalette.of(context).border,
                        text: IdeWbPalette.of(context).text2,
                      ),
              ),
            ),
          ),
          const SizedBox(height: WebTuiSpacing.sm),
          Wrap(
            spacing: WebTuiSpacing.md,
            runSpacing: WebTuiSpacing.xs,
            children: [
              for (var i = 0; i < legendNames.length; i++)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: palette[i % palette.length],
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        pie
                            ? '${legendNames[i]}: '
                                  '${ideFormatNumber(spec.series.first.values[i], spec.unit)}'
                            : legendNames[i].isEmpty
                            ? '${tr('Chuỗi', 'Series')} ${i + 1}'
                            : legendNames[i],
                        style: IdeType.bodySmall.copyWith(
                          color: IdeWbPalette.of(context).text,
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              style: TextButton.styleFrom(
                minimumSize: const Size(44, 44),
                padding: const EdgeInsets.symmetric(horizontal: 4),
              ),
              onPressed: () => setState(() => _showTable = !_showTable),
              child: Text(
                _showTable
                    ? tr('Ẩn bảng số liệu', 'Hide data table')
                    : tr('Xem bảng số liệu', 'Show data table'),
              ),
            ),
          ),
          if (_showTable) _DataTable(spec: spec),
        ],
      ),
    );
  }
}

class _DataTable extends StatelessWidget {
  const _DataTable({required this.spec});

  final IdeChartSpec spec;

  @override
  Widget build(BuildContext context) {
    final style = IdeType.bodySmall.copyWith(
      color: IdeWbPalette.of(context).textStrong,
    );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowHeight: 36,
        dataRowMinHeight: 32,
        dataRowMaxHeight: 40,
        columns: [
          DataColumn(label: Text('', style: style)),
          for (final s in spec.series)
            DataColumn(label: Text(s.name, style: style), numeric: true),
        ],
        rows: [
          for (var i = 0; i < spec.labels.length; i++)
            DataRow(
              cells: [
                DataCell(Text(spec.labels[i], style: style)),
                for (final s in spec.series)
                  DataCell(
                    Text(ideFormatNumber(s.values[i], spec.unit), style: style),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

TextPainter _tp(String text, Color color, {double size = 10.5}) => TextPainter(
  text: TextSpan(
    text: text,
    style: TextStyle(color: color, fontSize: size),
  ),
  textDirection: TextDirection.ltr,
  maxLines: 1,
  ellipsis: '…',
);

class _AxisPainter extends CustomPainter {
  _AxisPainter(
    this.spec,
    this.palette, {
    required this.grid,
    required this.text,
  });

  final IdeChartSpec spec;
  final List<Color> palette;
  final Color grid;
  final Color text;

  @override
  void paint(Canvas canvas, Size size) {
    var maxV = 0.0;
    var minV = 0.0;
    for (final s in spec.series) {
      for (final v in s.values) {
        if (v == null) continue;
        maxV = math.max(maxV, v);
        minV = math.min(minV, v);
      }
    }
    final top = _niceMax(maxV <= 0 ? 1 : maxV);
    final bottom = minV < 0 ? -_niceMax(-minV) : 0.0;
    const left = 44.0;
    const bottomPad = 22.0;
    const topPad = 8.0;
    final plotW = size.width - left - 4;
    final plotH = size.height - bottomPad - topPad;
    double yOf(double v) =>
        topPad + plotH * (1 - (v - bottom) / (top - bottom));

    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final v = bottom + (top - bottom) * i / 4;
      final y = yOf(v);
      canvas.drawLine(Offset(left, y), Offset(size.width, y), gridPaint);
      final tp = _tp(ideFormatNumber(v, ''), text)..layout(maxWidth: left - 4);
      tp.paint(canvas, Offset(left - 6 - tp.width, y - tp.height / 2));
    }

    final n = spec.labels.length;
    final step = plotW / n;
    // Nhãn trục X thưa dần khi nhiều nhãn.
    final every = math.max(1, (n / math.max(1, (plotW / 46).floor())).ceil());
    for (var i = 0; i < n; i += every) {
      final l = spec.labels[i];
      final tp = _tp(l.length > 10 ? '${l.substring(0, 9)}…' : l, text)
        ..layout(maxWidth: step * every);
      tp.paint(
        canvas,
        Offset(
          left + step * (i + 0.5) - tp.width / 2,
          size.height - bottomPad + 5,
        ),
      );
    }

    if (spec.type == IdeChartType.bar) {
      final k = spec.series.length;
      final groupW = step * 0.78;
      final barW = groupW / k;
      final zeroY = yOf(0);
      for (var si = 0; si < k; si++) {
        final paint = Paint()..color = palette[si % palette.length];
        for (var i = 0; i < n; i++) {
          final v = spec.series[si].values[i];
          if (v == null) continue;
          final x = left + step * i + (step - groupW) / 2 + barW * si;
          final y = yOf(v);
          canvas.drawRRect(
            RRect.fromRectAndCorners(
              Rect.fromLTRB(
                x + 1,
                math.min(y, zeroY),
                x + barW - 1,
                math.max(y, zeroY),
              ),
              topLeft: const Radius.circular(3),
              topRight: const Radius.circular(3),
            ),
            paint,
          );
        }
      }
    } else {
      for (var si = 0; si < spec.series.length; si++) {
        final color = palette[si % palette.length];
        final line = Paint()
          ..color = color
          ..strokeWidth = 2.4
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round;
        final dot = Paint()..color = color;
        final path = Path();
        var pen = false;
        for (var i = 0; i < n; i++) {
          final v = spec.series[si].values[i];
          if (v == null) {
            pen = false;
            continue;
          }
          final p = Offset(left + step * (i + 0.5), yOf(v));
          if (pen) {
            path.lineTo(p.dx, p.dy);
          } else {
            path.moveTo(p.dx, p.dy);
            pen = true;
          }
        }
        canvas.drawPath(path, line);
        // Chuỗi dày điểm (> 60) chỉ vẽ đường, chấm tròn chỉ làm rối.
        if (!ideChartShowDots(n)) continue;
        for (var i = 0; i < n; i++) {
          final v = spec.series[si].values[i];
          if (v == null) continue;
          canvas.drawCircle(Offset(left + step * (i + 0.5), yOf(v)), 3.2, dot);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_AxisPainter old) =>
      old.spec != spec || old.grid != grid || old.palette != palette;
}

class _PiePainter extends CustomPainter {
  _PiePainter(this.spec, this.palette, this.gap);

  final IdeChartSpec spec;
  final List<Color> palette;
  final Color gap;

  @override
  void paint(Canvas canvas, Size size) {
    final values = spec.series.first.values;
    final total = values.fold<double>(0, (a, b) => a + (b ?? 0));
    if (total <= 0) return;
    final radius = math.min(size.width, size.height) / 2 - 4;
    final center = Offset(size.width / 2, size.height / 2);
    final rect = Rect.fromCircle(center: center, radius: radius);
    var start = -math.pi / 2;
    for (var i = 0; i < values.length; i++) {
      final v = values[i] ?? 0;
      if (v <= 0) continue;
      final sweep = v / total * math.pi * 2;
      canvas.drawArc(
        rect,
        start,
        sweep,
        true,
        Paint()..color = palette[i % palette.length],
      );
      canvas.drawArc(
        rect,
        start,
        sweep,
        true,
        Paint()
          ..color = gap
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      if (sweep > 0.35) {
        final mid = start + sweep / 2;
        final tp = _tp('${(v / total * 100).round()}%', Colors.white, size: 12)
          ..layout();
        final c = center + Offset(math.cos(mid), math.sin(mid)) * radius * 0.62;
        tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
      }
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_PiePainter old) =>
      old.spec != spec || old.palette != palette || old.gap != gap;
}

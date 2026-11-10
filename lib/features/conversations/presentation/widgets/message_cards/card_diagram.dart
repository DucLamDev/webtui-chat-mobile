import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../../design_system/tokens/webtui_colors.dart';
import '../../../../../design_system/tokens/webtui_radii.dart';
import '../../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../../design_system/tokens/webtui_typography.dart';
import '../../../domain/entities/message_card.dart';
import 'card_chart.dart' show messageCardSeriesColors;
import 'card_common.dart';

/// Sơ đồ của thẻ: xếp node theo tầng (theo chiều cạnh), vẽ node + mũi tên trong
/// khung cuộn ngang. Mã mermaid (nếu có) chỉ để xem / chép, không chạy.
class MessageCardDiagramView extends StatefulWidget {
  const MessageCardDiagramView({required this.diagram, super.key});

  final MessageCardDiagram diagram;

  @override
  State<MessageCardDiagramView> createState() => _MessageCardDiagramViewState();
}

class _MessageCardDiagramViewState extends State<MessageCardDiagramView> {
  bool _showCode = false;
  MessageCardDiagramLayout? _layout;
  MessageCardDiagram? _layoutFor;

  MessageCardDiagramLayout get _currentLayout {
    if (_layout == null || !identical(_layoutFor, widget.diagram)) {
      _layout = layoutMessageCardDiagram(widget.diagram);
      _layoutFor = widget.diagram;
    }
    return _layout!;
  }

  @override
  Widget build(BuildContext context) {
    final diagram = widget.diagram;
    final mermaid = diagram.mermaid;
    final layout = _currentLayout;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (diagram.nodes.isEmpty)
          const MessageCardEmptyNote('Sơ đồ chưa có bước nào.')
        else
          Semantics(
            container: true,
            label: _semanticLabel(diagram),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: WebTuiColors.background,
                border: Border.all(color: WebTuiColors.border),
                borderRadius: BorderRadius.circular(WebTuiRadii.sm),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(WebTuiRadii.sm),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: CustomPaint(
                    size: layout.size,
                    painter: MessageCardDiagramPainter(
                      diagram: diagram,
                      layout: layout,
                      textStyle: WebTuiTypography.labelSmall.copyWith(
                        color: WebTuiColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                      edgeLabelStyle: WebTuiTypography.labelSmall.copyWith(
                        color: WebTuiColors.textSecondary,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (mermaid != null) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: WebTuiSpacing.xs,
                ),
                minimumSize: const Size(44, 36),
              ),
              onPressed: () => setState(() => _showCode = !_showCode),
              icon: Icon(
                _showCode ? Icons.expand_less_rounded : Icons.code_rounded,
                size: 18,
              ),
              label: Text(_showCode ? 'Ẩn mã' : 'Xem mã'),
            ),
          ),
          if (_showCode)
            DecoratedBox(
              decoration: BoxDecoration(
                color: WebTuiColors.backgroundMuted,
                borderRadius: BorderRadius.circular(WebTuiRadii.sm),
              ),
              child: Padding(
                padding: const EdgeInsets.all(WebTuiSpacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Text(
                        mermaid,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          color: WebTuiColors.textPrimary,
                          height: 1.4,
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () => _copyCode(context, mermaid),
                        icon: const Icon(Icons.copy_rounded, size: 16),
                        label: const Text('Chép mã'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }

  Future<void> _copyCode(BuildContext context, String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(const SnackBar(content: Text('Đã chép mã sơ đồ.')));
  }
}

String _semanticLabel(MessageCardDiagram diagram) {
  final steps = diagram.nodes.map((node) => node.label).take(12).join(', ');
  return 'Sơ đồ ${diagram.nodes.length} bước: $steps';
}

/// Vị trí node của sơ đồ (đơn vị điểm ảnh logic).
final class MessageCardDiagramLayout {
  const MessageCardDiagramLayout({required this.nodeRects, required this.size});

  final Map<String, Rect> nodeRects;
  final Size size;
}

const double _nodeWidth = 124;
const double _nodeHeight = 44;
const double _layerGap = 56;
const double _siblingGap = 16;
const double _padding = 12;

/// Xếp node theo tầng: tầng = đường dài nhất từ node gốc (bỏ cạnh tạo vòng),
/// trong tầng xếp theo vị trí trung bình của node cha để bớt cạnh chéo.
MessageCardDiagramLayout layoutMessageCardDiagram(MessageCardDiagram diagram) {
  final nodes = diagram.nodes;
  if (nodes.isEmpty) {
    return const MessageCardDiagramLayout(nodeRects: {}, size: Size(0, 0));
  }
  final order = {for (var i = 0; i < nodes.length; i++) nodes[i].id: i};
  final outgoing = <String, List<String>>{
    for (final node in nodes) node.id: <String>[],
  };
  for (final edge in diagram.edges) {
    if (edge.from == edge.to) continue;
    outgoing[edge.from]?.add(edge.to);
  }

  // Bỏ cạnh quay lui (tạo vòng) bằng DFS theo thứ tự node khai báo.
  final forward = <String, List<String>>{
    for (final node in nodes) node.id: <String>[],
  };
  final state = <String, int>{}; // 1 = đang đi, 2 = xong
  void visit(String id) {
    state[id] = 1;
    for (final next in outgoing[id]!) {
      final mark = state[next];
      if (mark == 1) continue; // cạnh tạo vòng
      forward[id]!.add(next);
      if (mark == null) visit(next);
    }
    state[id] = 2;
  }

  for (final node in nodes) {
    if (state[node.id] == null) visit(node.id);
  }

  // Tầng = đường dài nhất (đồ thị đã không còn vòng; thứ tự topo bằng DFS).
  final topo = <String>[];
  final seen = <String>{};
  void topoVisit(String id) {
    if (!seen.add(id)) return;
    for (final next in forward[id]!) {
      topoVisit(next);
    }
    topo.add(id);
  }

  for (final node in nodes) {
    topoVisit(node.id);
  }
  final layer = <String, int>{for (final node in nodes) node.id: 0};
  for (final id in topo.reversed) {
    for (final next in forward[id]!) {
      layer[next] = math.max(layer[next]!, layer[id]! + 1);
    }
  }

  final layerCount = layer.values.fold<int>(0, math.max) + 1;
  final layers = List.generate(layerCount, (_) => <String>[]);
  for (final node in nodes) {
    layers[layer[node.id]!].add(node.id);
  }
  // Sắp trong tầng theo trung bình vị trí node cha ở tầng trước.
  final position = <String, double>{};
  for (var index = 0; index < layers.first.length; index++) {
    position[layers.first[index]] = index.toDouble();
  }
  final parents = <String, List<String>>{
    for (final node in nodes) node.id: <String>[],
  };
  forward.forEach((from, targets) {
    for (final to in targets) {
      parents[to]!.add(from);
    }
  });
  for (var l = 1; l < layerCount; l++) {
    double key(String id) {
      final placed = parents[id]!.where(position.containsKey).toList();
      if (placed.isEmpty) return order[id]!.toDouble() + 1000;
      return placed.map((p) => position[p]!).reduce((a, b) => a + b) /
          placed.length;
    }

    layers[l].sort((a, b) {
      final byKey = key(a).compareTo(key(b));
      return byKey != 0 ? byKey : order[a]!.compareTo(order[b]!);
    });
    for (var index = 0; index < layers[l].length; index++) {
      position[layers[l][index]] = index.toDouble();
    }
  }

  final horizontal =
      diagram.direction == MessageCardDiagramDirection.leftToRight;
  final widest = layers.fold<int>(
    0,
    (max, items) => math.max(max, items.length),
  );
  final crossSpan = (horizontal ? _nodeHeight : _nodeWidth);
  final crossTotal = widest * crossSpan + (widest - 1) * _siblingGap;
  final rects = <String, Rect>{};
  for (var l = 0; l < layerCount; l++) {
    final items = layers[l];
    final span = items.length * crossSpan + (items.length - 1) * _siblingGap;
    final offset = (crossTotal - span) / 2;
    for (var index = 0; index < items.length; index++) {
      final cross = _padding + offset + index * (crossSpan + _siblingGap);
      final main =
          _padding + l * ((horizontal ? _nodeWidth : _nodeHeight) + _layerGap);
      rects[items[index]] = horizontal
          ? Rect.fromLTWH(main, cross, _nodeWidth, _nodeHeight)
          : Rect.fromLTWH(cross, main, _nodeWidth, _nodeHeight);
    }
  }
  final mainTotal =
      layerCount * (horizontal ? _nodeWidth : _nodeHeight) +
      (layerCount - 1) * _layerGap;
  return MessageCardDiagramLayout(
    nodeRects: rects,
    size: horizontal
        ? Size(mainTotal + _padding * 2, crossTotal + _padding * 2)
        : Size(crossTotal + _padding * 2, mainTotal + _padding * 2),
  );
}

class MessageCardDiagramPainter extends CustomPainter {
  MessageCardDiagramPainter({
    required this.diagram,
    required this.layout,
    required this.textStyle,
    required this.edgeLabelStyle,
  });

  final MessageCardDiagram diagram;
  final MessageCardDiagramLayout layout;
  final TextStyle textStyle;
  final TextStyle edgeLabelStyle;

  @override
  void paint(Canvas canvas, Size size) {
    if (layout.nodeRects.isEmpty) return;
    final groupColors = <String, Color>{};
    for (final node in diagram.nodes) {
      final group = node.group;
      if (group != null && !groupColors.containsKey(group)) {
        groupColors[group] =
            messageCardSeriesColors[groupColors.length %
                messageCardSeriesColors.length];
      }
    }

    final edgePaint = Paint()
      ..color = WebTuiColors.textSecondary
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final labels = <(Offset, String)>[];
    for (final edge in diagram.edges) {
      final from = layout.nodeRects[edge.from];
      final to = layout.nodeRects[edge.to];
      if (from == null || to == null) continue;
      if (edge.from == edge.to) {
        _paintSelfLoop(canvas, from, edgePaint);
        continue;
      }
      final start = _borderPoint(from, to.center);
      final end = _borderPoint(to, from.center);
      canvas.drawLine(start, end, edgePaint);
      _paintArrowHead(canvas, start, end, edgePaint.color);
      final label = edge.label;
      if (label != null) labels.add(((start + end) / 2, label));
    }

    for (final node in diagram.nodes) {
      final rect = layout.nodeRects[node.id];
      if (rect == null) continue;
      final accent = node.group == null
          ? WebTuiColors.primary
          : groupColors[node.group]!;
      final rrect = RRect.fromRectAndRadius(
        rect,
        const Radius.circular(WebTuiRadii.sm),
      );
      canvas
        ..drawRRect(rrect, Paint()..color = WebTuiColors.surface)
        ..drawRRect(
          rrect,
          Paint()
            ..color = accent
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        )
        ..drawRect(
          Rect.fromLTWH(rect.left, rect.top + 6, 3, rect.height - 12),
          Paint()..color = accent,
        );
      final text = TextPainter(
        text: TextSpan(text: node.label, style: textStyle),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
        maxLines: 2,
        ellipsis: '…',
      )..layout(maxWidth: rect.width - 14);
      text.paint(
        canvas,
        Offset(
          rect.left + 7 + (rect.width - 14 - text.width) / 2,
          rect.center.dy - text.height / 2,
        ),
      );
    }

    // Nhãn cạnh vẽ sau cùng, có nền để không bị đường đè lên.
    for (final (center, label) in labels) {
      final text = TextPainter(
        text: TextSpan(text: label, style: edgeLabelStyle),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: 96);
      final box = Rect.fromCenter(
        center: center,
        width: text.width + 8,
        height: text.height + 4,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(box, const Radius.circular(4)),
        Paint()..color = WebTuiColors.background,
      );
      text.paint(canvas, Offset(box.left + 4, box.top + 2));
    }
  }

  /// Điểm trên viền [rect] theo hướng tới [target].
  Offset _borderPoint(Rect rect, Offset target) {
    final center = rect.center;
    final dx = target.dx - center.dx;
    final dy = target.dy - center.dy;
    if (dx == 0 && dy == 0) return center;
    final scaleX = dx == 0 ? double.infinity : (rect.width / 2) / dx.abs();
    final scaleY = dy == 0 ? double.infinity : (rect.height / 2) / dy.abs();
    final scale = math.min(scaleX, scaleY);
    return Offset(center.dx + dx * scale, center.dy + dy * scale);
  }

  void _paintArrowHead(Canvas canvas, Offset start, Offset end, Color color) {
    final direction = end - start;
    final length = direction.distance;
    if (length < 1) return;
    final unit = direction / length;
    final normal = Offset(-unit.dy, unit.dx);
    const size = 7.0;
    final path = Path()
      ..moveTo(end.dx, end.dy)
      ..lineTo(
        end.dx - unit.dx * size + normal.dx * size * 0.55,
        end.dy - unit.dy * size + normal.dy * size * 0.55,
      )
      ..lineTo(
        end.dx - unit.dx * size - normal.dx * size * 0.55,
        end.dy - unit.dy * size - normal.dy * size * 0.55,
      )
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  void _paintSelfLoop(Canvas canvas, Rect rect, Paint paint) {
    final start = Offset(rect.right - 18, rect.top);
    final end = Offset(rect.right, rect.top + 14);
    final path = Path()
      ..moveTo(start.dx, start.dy)
      ..cubicTo(start.dx, start.dy - 18, end.dx + 18, end.dy, end.dx, end.dy);
    canvas.drawPath(path, paint);
    _paintArrowHead(canvas, Offset(end.dx + 10, end.dy), end, paint.color);
  }

  @override
  bool shouldRepaint(covariant MessageCardDiagramPainter oldDelegate) =>
      !identical(oldDelegate.diagram, diagram) ||
      !identical(oldDelegate.layout, layout) ||
      oldDelegate.textStyle != textStyle;
}

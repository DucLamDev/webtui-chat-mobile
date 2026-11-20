import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../../design_system/tokens/webtui_radii.dart';
import '../../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../../l10n/app_strings.dart';
import '../ide_wb.dart';
import 'ide_blocks_model.dart';

/// Sơ đồ (vùng / nút / mũi tên) tự vẽ. Trong tin: thu vừa bề rộng, chạm mở
/// toàn màn để phóng to / kéo ([InteractiveViewer]).
class IdeDiagramView extends StatelessWidget {
  const IdeDiagramView({required this.spec, super.key});

  final IdeDiagramSpec spec;

  @override
  Widget build(BuildContext context) {
    final layout = layoutIdeDiagram(spec);
    if (layout.height <= 0) return const SizedBox.shrink();
    return Semantics(
      button: true,
      label:
          '${tr('Sơ đồ', 'Diagram')}: ${spec.nodes.map((n) => n.name).join(', ')}. '
          '${tr('Chạm để phóng to', 'Tap to enlarge')}',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context).push(
          IdePageRoute<void>(
            fullscreenDialog: true,
            builder: (_) => IdeDiagramFullScreen(spec: spec),
          ),
        ),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: WebTuiSpacing.sm),
          padding: const EdgeInsets.all(WebTuiSpacing.sm),
          decoration: BoxDecoration(
            color: IdeWbPalette.of(context).bg,
            borderRadius: BorderRadius.circular(WebTuiRadii.md),
            border: Border.all(color: IdeWbPalette.of(context).border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 360),
                child: FittedBox(
                  alignment: Alignment.topCenter,
                  fit: BoxFit.scaleDown,
                  child: _DiagramCanvas(spec: spec, layout: layout),
                ),
              ),
              const SizedBox(height: WebTuiSpacing.xs),
              Row(
                children: [
                  Icon(
                    Icons.zoom_out_map_rounded,
                    size: 16,
                    color: IdeWbPalette.of(context).text2,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    tr('Chạm để phóng to', 'Tap to enlarge'),
                    style: IdeType.bodySmall.copyWith(
                      color: IdeWbPalette.of(context).text2,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class IdeDiagramFullScreen extends StatelessWidget {
  const IdeDiagramFullScreen({required this.spec, super.key});

  final IdeDiagramSpec spec;

  @override
  Widget build(BuildContext context) {
    final layout = layoutIdeDiagram(spec);
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Sơ đồ', 'Diagram')),
        leading: IconButton(
          tooltip: tr('Đóng', 'Close'),
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: InteractiveViewer(
        minScale: 0.4,
        maxScale: 5,
        boundaryMargin: const EdgeInsets.all(120),
        constrained: false,
        child: Padding(
          padding: const EdgeInsets.all(WebTuiSpacing.lg),
          child: _DiagramCanvas(spec: spec, layout: layout),
        ),
      ),
    );
  }
}

class _DiagramCanvas extends StatelessWidget {
  const _DiagramCanvas({required this.spec, required this.layout});

  final IdeDiagramSpec spec;
  final IdeDiagramLayout layout;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(layout.width, layout.height),
      painter: _DiagramPainter(
        spec,
        layout,
        brightness: IdeWbPalette.of(context).brightness,
        primary: IdeWbPalette.of(context).accentInk,
        surface: IdeWbPalette.of(context).bg,
        band: IdeWbPalette.of(context).chip,
        border: IdeWbPalette.of(context).border,
        text: IdeWbPalette.of(context).textStrong,
        muted: IdeWbPalette.of(context).text2,
        edge: IdeWbPalette.of(context).text,
      ),
    );
  }
}

class _DiagramPainter extends CustomPainter {
  _DiagramPainter(
    this.spec,
    this.layout, {
    required this.brightness,
    required this.primary,
    required this.surface,
    required this.band,
    required this.border,
    required this.text,
    required this.muted,
    required this.edge,
  });

  final IdeDiagramSpec spec;
  final IdeDiagramLayout layout;
  final Brightness brightness;
  final Color primary;
  final Color surface;
  final Color band;
  final Color border;
  final Color text;
  final Color muted;
  final Color edge;

  TextPainter _text(
    String s,
    Color c,
    double size,
    double maxW, {
    FontWeight weight = FontWeight.w500,
  }) => TextPainter(
    text: TextSpan(
      text: s,
      style: TextStyle(color: c, fontSize: size, fontWeight: weight),
    ),
    textDirection: TextDirection.ltr,
    maxLines: 1,
    ellipsis: '…',
    textAlign: TextAlign.center,
  )..layout(maxWidth: maxW);

  @override
  void paint(Canvas canvas, Size size) {
    for (final b in layout.bands) {
      final r = Rect.fromLTWH(b.rect.x, b.rect.y, b.rect.w, b.rect.h);
      final rr = RRect.fromRectAndRadius(r, const Radius.circular(12));
      canvas.drawRRect(rr, Paint()..color = band);
      canvas.drawRRect(
        rr,
        Paint()
          ..color = border
          ..style = PaintingStyle.stroke,
      );
      _text(
        b.zone.name,
        muted,
        11,
        r.width - 20,
        weight: FontWeight.w700,
      ).paint(canvas, Offset(r.left + 10, r.top + 5));
    }
    // Mũi tên trước, nút đè lên.
    for (final e in spec.edges) {
      final a = layout.nodeRects[e.from];
      final b = layout.nodeRects[e.to];
      if (a == null || b == null) continue;
      _arrow(canvas, a, b, e);
    }
    final nodeFill = Paint()..color = surface;
    final nodeLine = Paint()
      ..color = primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    for (final n in spec.nodes) {
      final p = layout.nodeRects[n.id];
      if (p == null) continue;
      final r = Rect.fromLTWH(p.x, p.y, ideDiagramNodeW, ideDiagramNodeH);
      final rr = RRect.fromRectAndRadius(r, const Radius.circular(10));
      canvas.drawRRect(rr, nodeFill);
      canvas.drawRRect(rr, nodeLine);
      final name = _text(
        n.name,
        text,
        12,
        ideDiagramNodeW - 12,
        weight: FontWeight.w700,
      );
      final hasType = n.type.isNotEmpty;
      final total = name.height + (hasType ? 13 : 0);
      var y = r.top + (ideDiagramNodeH - total) / 2;
      name.paint(canvas, Offset(r.left + (r.width - name.width) / 2, y));
      if (hasType) {
        y += name.height + 1;
        final t = _text(n.type, muted, 10, ideDiagramNodeW - 12);
        t.paint(canvas, Offset(r.left + (r.width - t.width) / 2, y));
      }
    }
  }

  void _arrow(
    Canvas canvas,
    ({double x, double y}) a,
    ({double x, double y}) b,
    IdeDiagramEdge e,
  ) {
    final ca = Offset(a.x + ideDiagramNodeW / 2, a.y + ideDiagramNodeH / 2);
    final cb = Offset(b.x + ideDiagramNodeW / 2, b.y + ideDiagramNodeH / 2);
    if ((ca - cb).distance < 1) return;
    final ra = Rect.fromLTWH(a.x, a.y, ideDiagramNodeW, ideDiagramNodeH);
    final rb = Rect.fromLTWH(b.x, b.y, ideDiagramNodeW, ideDiagramNodeH);
    final start = _clip(ra, ca, cb);
    final end = _clip(rb, cb, ca);
    final paint = Paint()
      ..color = edge
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawLine(start, end, paint);
    final angle = math.atan2(end.dy - start.dy, end.dx - start.dx);
    const head = 8.0;
    final path = Path()
      ..moveTo(end.dx, end.dy)
      ..lineTo(
        end.dx - head * math.cos(angle - 0.45),
        end.dy - head * math.sin(angle - 0.45),
      )
      ..lineTo(
        end.dx - head * math.cos(angle + 0.45),
        end.dy - head * math.sin(angle + 0.45),
      )
      ..close();
    canvas.drawPath(path, Paint()..color = edge);
    final label = [e.proto, e.data].where((s) => s.isNotEmpty).join(' · ');
    if (label.isNotEmpty) {
      final mid = Offset.lerp(start, end, 0.5)!;
      final tp = _text(label, muted, 9.5, 110);
      final rect = Rect.fromCenter(
        center: mid,
        width: tp.width + 6,
        height: tp.height + 2,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(4)),
        Paint()..color = surface.withValues(alpha: 0.92),
      );
      tp.paint(canvas, Offset(rect.left + 3, rect.top + 1));
    }
  }

  /// Giao điểm đoạn nối tâm với mép hình chữ nhật.
  Offset _clip(Rect r, Offset from, Offset to) {
    final d = to - from;
    final sx = d.dx == 0 ? double.infinity : (r.width / 2) / d.dx.abs();
    final sy = d.dy == 0 ? double.infinity : (r.height / 2) / d.dy.abs();
    final s = math.min(sx, sy);
    return from + d * s;
  }

  @override
  bool shouldRepaint(_DiagramPainter old) =>
      old.spec != spec || old.brightness != brightness || old.layout != layout;
}

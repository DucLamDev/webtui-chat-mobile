import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Chụm 2 ngón đổi cỡ chữ. Dùng `Listener` (không vào đấu cử chỉ) để không
/// cản cuộn / chọn chữ của terminal. [onScale] nhận tỉ lệ so với lúc đặt ngón.
class IdeTermPinch extends StatefulWidget {
  const IdeTermPinch({
    required this.child,
    required this.onStart,
    required this.onScale,
    super.key,
  });

  final Widget child;
  final VoidCallback onStart;
  final ValueChanged<double> onScale;

  @override
  State<IdeTermPinch> createState() => _IdeTermPinchState();
}

class _IdeTermPinchState extends State<IdeTermPinch> {
  final _points = <int, Offset>{};
  double _startDistance = 0;

  double _distance() {
    final p = _points.values.take(2).toList();
    return (p[0] - p[1]).distance;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (e) {
        _points[e.pointer] = e.position;
        if (_points.length == 2) {
          _startDistance = math.max(_distance(), 1);
          widget.onStart();
        }
      },
      onPointerMove: (e) {
        if (!_points.containsKey(e.pointer)) return;
        _points[e.pointer] = e.position;
        if (_points.length == 2 && _startDistance > 0) {
          widget.onScale(_distance() / _startDistance);
        }
      },
      onPointerUp: (e) => _points.remove(e.pointer),
      onPointerCancel: (e) => _points.remove(e.pointer),
      child: widget.child,
    );
  }
}

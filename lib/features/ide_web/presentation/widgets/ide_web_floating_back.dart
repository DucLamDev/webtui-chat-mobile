import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ide_web_back_button.dart';

/// Chỗ đậu của nút quay lại: mép phải hay trái, và độ cao theo tỉ lệ
/// (0 = sát trên, 1 = sát dưới) để vẫn đúng chỗ khi khung đổi cao.
@immutable
class IdeWebBackDock {
  const IdeWebBackDock({required this.right, required this.y});

  static const initial = IdeWebBackDock(right: false, y: 1);

  final bool right;
  final double y;

  @override
  bool operator ==(Object other) =>
      other is IdeWebBackDock && other.right == right && other.y == y;

  @override
  int get hashCode => Object.hash(right, y);
}

/// Nhớ suốt lúc app còn chạy, như trang IDE đang giữ.
final ideWebBackDockProvider = StateProvider<IdeWebBackDock>(
  (_) => IdeWebBackDock.initial,
);

/// Lớp phủ kín vùng trang IDE, chỉ chứa nút quay lại (kéo được, thả ra thì hít
/// vào mép gần nhất) và chỉ báo thu nằm cạnh nút, phía giữa màn. Chỗ trống
/// không nhận chạm: trang IDE bên dưới vẫn bấm được.
class IdeWebFloatingBack extends ConsumerStatefulWidget {
  const IdeWebFloatingBack({
    required this.onPressed,
    required this.capturing,
    this.showBack = true,
    super.key,
  });

  final VoidCallback onPressed;
  final ValueListenable<bool> capturing;

  /// `false` khi bàn phím đang mở: ẩn nút, chỉ còn chỉ báo thu (nếu có).
  final bool showBack;

  @override
  ConsumerState<IdeWebFloatingBack> createState() => _IdeWebFloatingBackState();
}

class _IdeWebFloatingBackState extends ConsumerState<IdeWebFloatingBack> {
  static const _margin = 12.0;
  static const _gap = 8.0;
  static const _size = IdeWebBackButton.size;

  /// Góc trên trái của nút khi đang kéo.
  Offset? _drag;

  @override
  Widget build(BuildContext context) {
    final dock = ref.watch(ideWebBackDockProvider);
    return LayoutBuilder(
      builder: (context, box) {
        final maxX = (box.maxWidth - _size - _margin).clamp(_margin, 1e9);
        final maxY = (box.maxHeight - _size - _margin).clamp(_margin, 1e9);
        final drag = _drag;
        final left = drag?.dx ?? (dock.right ? maxX : _margin);
        final top = drag?.dy ?? _margin + (maxY - _margin) * dock.y;
        // Chỉ báo nằm phía giữa màn so với nút.
        final right = drag == null ? dock.right : left > (_margin + maxX) / 2;
        final duration = drag != null || MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 220);

        void drop() {
          final at = _drag;
          if (at == null) return;
          ref.read(ideWebBackDockProvider.notifier).state = IdeWebBackDock(
            right: at.dx > (_margin + maxX) / 2,
            y: maxY > _margin
                ? ((at.dy - _margin) / (maxY - _margin)).clamp(0.0, 1.0)
                : 1.0,
          );
          setState(() => _drag = null);
        }

        final badgeOffset = widget.showBack ? _size + _gap : 0.0;
        return Stack(
          children: [
            if (widget.showBack)
              AnimatedPositioned(
                duration: duration,
                curve: Curves.easeOutCubic,
                left: left,
                top: top,
                child: GestureDetector(
                  key: const Key('ide_web_back_drag'),
                  // Tính cả đoạn trước khi nhận ra là kéo: nút bám đúng ngón tay.
                  dragStartBehavior: DragStartBehavior.down,
                  onPanStart: (_) => setState(() => _drag = Offset(left, top)),
                  onPanUpdate: (details) {
                    final at = (_drag ?? Offset(left, top)) + details.delta;
                    setState(
                      () => _drag = Offset(
                        at.dx.clamp(_margin, maxX),
                        at.dy.clamp(_margin, maxY),
                      ),
                    );
                  },
                  onPanEnd: (_) => drop(),
                  onPanCancel: drop,
                  child: IdeWebBackButton(onPressed: widget.onPressed),
                ),
              ),
            AnimatedPositioned(
              duration: duration,
              curve: Curves.easeOutCubic,
              top: top,
              height: _size,
              left: right ? null : left + badgeOffset,
              right: right ? box.maxWidth - left - _size + badgeOffset : null,
              child: Center(child: IdeWebMicBadge(capturing: widget.capturing)),
            ),
          ],
        );
      },
    );
  }
}

import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../../../design_system/icons/webtui_icons.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../../../../l10n/app_strings.dart';

/// Một ô trong lưới thao tác tin nhắn (biểu tượng màu ở trên, nhãn ở dưới, kiểu Zalo).
class MessageActionItem {
  const MessageActionItem({
    required this.id,
    required this.label,
    required this.icon,
    required this.color,
    required this.onSelected,
  });

  /// Mã ổn định cho test (`message-action-<id>`).
  final String id;
  final String label;
  final IconData icon;

  /// Màu biểu tượng (nền sáng); nền tối tự làm sáng hơn cho đủ tương phản.
  final Color color;

  /// Chạy SAU khi lớp thao tác đã đóng.
  final VoidCallback onSelected;
}

/// Sáu cảm xúc nhanh như Zalo: tim, thích, haha, wow, khóc, giận.
const messageQuickReactions = <String>[
  '\u{2764}\u{FE0F}',
  '\u{1F44D}',
  '\u{1F606}',
  '\u{1F62E}',
  '\u{1F62D}',
  '\u{1F621}',
];

/// Lớp thao tác khi nhấn giữ tin nhắn: nền mờ, thanh cảm xúc, bản xem tin nhắn và lưới thao tác.
/// [anchor] là điểm ngón tay nhấn giữ (toạ độ màn hình); null thì đặt giữa màn hình.
Future<void> showMessageActionOverlay(
  BuildContext context, {
  required Offset? anchor,
  required bool isMine,
  required String previewText,
  required List<MessageActionItem> actions,
  Set<String> selectedReactions = const {},
  ValueChanged<String>? onReact,
  VoidCallback? onMoreReactions,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: tr('Đóng thao tác tin nhắn', 'Close message actions'),
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 160),
    pageBuilder: (dialogContext, _, _) => _MessageActionOverlay(
      anchor: anchor,
      isMine: isMine,
      previewText: previewText,
      actions: actions,
      selectedReactions: selectedReactions,
      onReact: onReact,
      onMoreReactions: onMoreReactions,
    ),
    transitionBuilder: (context, animation, _, child) {
      // Máy bật giảm chuyển động: hiện / ẩn ngay, không phóng, không mờ dần.
      if (MediaQuery.disableAnimationsOf(context)) return child;
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.97, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _MessageActionOverlay extends StatelessWidget {
  const _MessageActionOverlay({
    required this.anchor,
    required this.isMine,
    required this.previewText,
    required this.actions,
    required this.selectedReactions,
    required this.onReact,
    required this.onMoreReactions,
  });

  final Offset? anchor;
  final bool isMine;
  final String previewText;
  final List<MessageActionItem> actions;
  final Set<String> selectedReactions;
  final ValueChanged<String>? onReact;
  final VoidCallback? onMoreReactions;

  void _closeThen(BuildContext context, VoidCallback? action) {
    Navigator.of(context).pop();
    action?.call();
  }

  @override
  Widget build(BuildContext context) {
    final dark = WebTuiColors.brightness == Brightness.dark;
    final media = MediaQuery.of(context);
    final cardWidth = math.min(media.size.width - 24, 380.0);
    final onReact = this.onReact;
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: isMine
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        if (onReact != null) ...[
          _QuickReactionBar(
            selected: selectedReactions,
            onSelected: (emoji) => _closeThen(context, () => onReact(emoji)),
            onMore: onMoreReactions == null
                ? null
                : () => _closeThen(context, onMoreReactions),
          ),
          const SizedBox(height: 8),
        ],
        _MessagePreviewBubble(
          text: previewText,
          isMine: isMine,
          maxWidth: cardWidth * 0.86,
        ),
        const SizedBox(height: 8),
        _ActionGrid(
          width: cardWidth,
          actions: actions,
          onSelected: (item) => _closeThen(context, item.onSelected),
        ),
      ],
    );
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              key: const ValueKey('message-action-backdrop'),
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).pop(),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: dark ? 0.55 : 0.38),
                ),
              ),
            ),
          ),
          CustomSingleChildLayout(
            delegate: _AnchoredLayout(
              anchor: anchor,
              // Bàn phím đang mở thì khối thao tác nằm trên bàn phím.
              padding: media.padding.copyWith(
                bottom: math.max(media.padding.bottom, media.viewInsets.bottom),
              ),
              alignEnd: isMine,
            ),
            child: SingleChildScrollView(child: content),
          ),
        ],
      ),
    );
  }
}

/// Đặt khối thao tác gần chỗ ngón tay, canh theo phía bong bóng (của mình: phải), luôn nằm trong vùng an toàn.
class _AnchoredLayout extends SingleChildLayoutDelegate {
  const _AnchoredLayout({
    required this.anchor,
    required this.padding,
    required this.alignEnd,
  });

  final Offset? anchor;
  final EdgeInsets padding;
  final bool alignEnd;

  static const _margin = 12.0;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return BoxConstraints.loose(
      Size(
        math.max(0, constraints.maxWidth - _margin * 2),
        math.max(0, constraints.maxHeight - padding.vertical - _margin * 2),
      ),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final x = alignEnd ? size.width - childSize.width - _margin : _margin;
    final minTop = padding.top + _margin;
    final maxTop = math.max(
      minTop,
      size.height - padding.bottom - _margin - childSize.height,
    );
    final anchor = this.anchor;
    // Thanh cảm xúc + đầu bản xem tin nằm ngay trên chỗ ngón tay.
    final desired = anchor == null
        ? (size.height - childSize.height) / 2
        : anchor.dy - 84;
    return Offset(x, desired.clamp(minTop, maxTop));
  }

  @override
  bool shouldRelayout(_AnchoredLayout oldDelegate) {
    return anchor != oldDelegate.anchor ||
        padding != oldDelegate.padding ||
        alignEnd != oldDelegate.alignEnd;
  }
}

class _QuickReactionBar extends StatelessWidget {
  const _QuickReactionBar({
    required this.selected,
    required this.onSelected,
    required this.onMore,
  });

  final Set<String> selected;
  final ValueChanged<String> onSelected;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    final dark = WebTuiColors.brightness == Brightness.dark;
    // Máy hẹp (320 pt) không đủ chỗ cho 7 nút 44 pt: thu nhỏ cả thanh thay vì tràn.
    return FittedBox(fit: BoxFit.scaleDown, child: _bar(dark));
  }

  Widget _bar(bool dark) {
    return Container(
      key: const ValueKey('message-quick-reactions'),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: _floatingDecoration(dark, radius: 28),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final emoji in messageQuickReactions)
            _ReactionButton(
              emoji: emoji,
              selected: selected.contains(emoji),
              onTap: () => onSelected(emoji),
            ),
          if (onMore != null)
            Semantics(
              button: true,
              label: tr('Thêm cảm xúc', 'More reactions'),
              excludeSemantics: true,
              child: InkResponse(
                key: const ValueKey('message-quick-reactions-more'),
                onTap: onMore,
                radius: 22,
                child: SizedBox.square(
                  dimension: 44,
                  child: Center(
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: WebTuiColors.chipBackground,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        WebTuiIcons.add,
                        size: 18,
                        color: WebTuiColors.textSecondary,
                      ),
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

class _ReactionButton extends StatelessWidget {
  const _ReactionButton({
    required this.emoji,
    required this.selected,
    required this.onTap,
  });

  final String emoji;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: emoji,
      excludeSemantics: true,
      child: InkResponse(
        key: ValueKey('message-quick-reaction-$emoji'),
        onTap: onTap,
        radius: 22,
        child: SizedBox.square(
          dimension: 44,
          child: Center(
            child: Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: selected
                  ? BoxDecoration(
                      color: WebTuiColors.primarySoft,
                      shape: BoxShape.circle,
                    )
                  : null,
              child: Text(
                emoji,
                style: const TextStyle(fontSize: 26, height: 1.1),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MessagePreviewBubble extends StatelessWidget {
  const _MessagePreviewBubble({
    required this.text,
    required this.isMine,
    required this.maxWidth,
  });

  final String text;
  final bool isMine;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final dark = WebTuiColors.brightness == Brightness.dark;
    const radius = Radius.circular(16);
    const tail = Radius.circular(4);
    return Container(
      key: const ValueKey('message-action-preview'),
      constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: 148),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isMine
            ? WebTuiColors.messageOutgoing
            : WebTuiColors.messageIncoming,
        borderRadius: BorderRadius.only(
          topLeft: radius,
          topRight: radius,
          bottomLeft: isMine ? radius : tail,
          bottomRight: isMine ? tail : radius,
        ),
        border: isMine && !dark
            ? Border.all(color: WebTuiColors.messageOutgoingBorder)
            : null,
      ),
      child: Text(
        text.trim().isEmpty ? tr('Tin nhắn', 'Message') : text.trim(),
        maxLines: 6,
        overflow: TextOverflow.ellipsis,
        style: WebTuiTypography.bodyMedium.copyWith(
          color: WebTuiColors.textPrimary,
        ),
      ),
    );
  }
}

class _ActionGrid extends StatelessWidget {
  const _ActionGrid({
    required this.width,
    required this.actions,
    required this.onSelected,
  });

  final double width;
  final List<MessageActionItem> actions;
  final ValueChanged<MessageActionItem> onSelected;

  static const _columns = 4;
  static const _padding = 8.0;

  @override
  Widget build(BuildContext context) {
    final dark = WebTuiColors.brightness == Brightness.dark;
    return Container(
      key: const ValueKey('message-action-grid'),
      width: width,
      padding: const EdgeInsets.symmetric(
        horizontal: _padding,
        vertical: _padding,
      ),
      decoration: _floatingDecoration(dark, radius: 16),
      // Độ rộng ô lấy từ chỗ trống thật (đã trừ viền nền tối), làm tròn xuống
      // để luôn đủ 4 cột trên một hàng.
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cellWidth = (constraints.maxWidth / _columns).floorToDouble();
          return Wrap(
            children: [
              for (final item in actions)
                SizedBox(
                  width: cellWidth,
                  child: _ActionCell(
                    item: item,
                    dark: dark,
                    onTap: () => onSelected(item),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ActionCell extends StatelessWidget {
  const _ActionCell({
    required this.item,
    required this.dark,
    required this.onTap,
  });

  final MessageActionItem item;
  final bool dark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final iconColor = dark
        ? Color.lerp(item.color, Colors.white, 0.32)!
        : item.color;
    return Semantics(
      button: true,
      label: item.label,
      excludeSemantics: true,
      child: InkWell(
        key: ValueKey('message-action-${item.id}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 76),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(item.icon, size: 26, color: iconColor),
                const SizedBox(height: 6),
                Text(
                  item.label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: WebTuiTypography.labelSmall.copyWith(
                    color: WebTuiColors.textPrimary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

BoxDecoration _floatingDecoration(bool dark, {required double radius}) {
  return BoxDecoration(
    color: WebTuiColors.surface,
    borderRadius: BorderRadius.circular(radius),
    border: dark
        ? Border.all(color: Colors.white.withValues(alpha: 0.08))
        : null,
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: dark ? 0.4 : 0.12),
        blurRadius: 20,
        offset: const Offset(0, 4),
      ),
    ],
  );
}

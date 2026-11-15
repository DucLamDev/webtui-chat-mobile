import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../icons/webtui_icons.dart';
import '../tokens/webtui_colors.dart';
import '../tokens/webtui_density.dart';
import '../tokens/webtui_typography.dart';
import 'webtui_bottom_inset.dart';

class WebTuiMobileScaffold extends StatelessWidget {
  const WebTuiMobileScaffold({
    required this.title,
    required this.body,
    required this.selectedTab,
    required this.onTabSelected,
    this.leading,
    this.actions = const [],
    this.floatingActionButton,
    this.showAppBar = true,
    this.tabBadges = const {},
    super.key,
  });

  /// Số hiện ở góc biểu tượng từng tab (chỉ số tab → số chưa đọc).
  final Map<int, int> tabBadges;

  /// `false`: bỏ thanh tiêu đề để màn có thêm chỗ (tab tự đặt nút của nó).
  final bool showAppBar;
  final String title;
  final Widget body;
  final int selectedTab;
  final ValueChanged<int> onTabSelected;
  final Widget? leading;
  final List<Widget> actions;
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: !showAppBar
          ? null
          : AppBar(
              toolbarHeight: 54,
              centerTitle: false,
              leading: leading,
              leadingWidth: leading == null ? 0 : 46,
              surfaceTintColor: Colors.transparent,
              shape: Border(
                bottom: BorderSide(
                  color: WebTuiColors.border.withValues(alpha: 0.7),
                ),
              ),
              titleSpacing: leading == null ? 16 : 0,
              title: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: WebTuiTypography.titleLarge.copyWith(
                  color: WebTuiColors.textPrimary,
                ),
              ),
              actions: actions,
            ),
      // Thanh tab nổi đè lên thân: nội dung cuộn ra phía sau thanh mờ. Thân
      // không tự chừa đáy; Scaffold đặt `MediaQuery.padding.bottom` của thân
      // bằng chiều cao thanh chiếm (gồm vùng an toàn), danh sách trong tab đệm
      // đáy theo [WebTuiFloatingTabBar.contentBottomPadding].
      extendBody: true,
      body: SafeArea(top: !showAppBar, bottom: false, child: body),
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: WebTuiFloatingTabBar(
        selectedIndex: selectedTab,
        onSelected: onTabSelected,
        badges: tabBadges,
      ),
    );
  }
}

class _TabSpec {
  const _TabSpec(this.icon, this.label);

  final IconData icon;
  final String label;
}

const _tabs = [
  _TabSpec(WebTuiIcons.messages, 'Tin nhắn'),
  _TabSpec(WebTuiIcons.friends, 'Bạn bè'),
  _TabSpec(WebTuiIcons.work, 'Công việc'),
  _TabSpec(WebTuiIcons.settings, 'Cài đặt'),
];

/// Bảng màu của thanh nổi theo nền sáng / tối.
class _TabBarPalette {
  const _TabBarPalette({
    required this.background,
    required this.border,
    required this.shadow,
    required this.selectedFill,
    required this.selected,
    required this.unselected,
  });

  factory _TabBarPalette.of(BuildContext context) {
    final theme = Theme.of(context);
    if (theme.brightness == Brightness.dark) {
      return _TabBarPalette(
        background: const Color(0xFF1F2329).withValues(alpha: 0.82),
        border: Colors.white.withValues(alpha: 0.10),
        shadow: Colors.black.withValues(alpha: 0.45),
        selectedFill: Colors.white.withValues(alpha: 0.12),
        selected: const Color(0xFF5AA9FF),
        unselected: Colors.white.withValues(alpha: 0.72),
      );
    }
    return _TabBarPalette(
      background: WebTuiColors.surface.withValues(alpha: 0.85),
      border: WebTuiColors.border.withValues(alpha: 0.9),
      shadow: const Color(0xFF1E3A64).withValues(alpha: 0.14),
      selectedFill: WebTuiColors.primarySoft,
      selected: theme.colorScheme.primary,
      unselected: WebTuiColors.textSecondary,
    );
  }

  final Color background;
  final Color border;
  final Color shadow;
  final Color selectedFill;
  final Color selected;
  final Color unselected;
}

/// Thanh tab nổi kiểu Telegram: viên thuốc bo tròn cách mép trái / phải, nằm
/// ngay trên thanh home; nền kính mờ trong suốt (blur) để nội dung cuộn phía
/// sau vẫn thấy mờ mờ; viền mảnh và bóng nhẹ. Mục đang chọn có nền viên thuốc
/// đậm hơn sau biểu tượng + chữ.
///
/// Dùng trong [WebTuiMobileScaffold] với `extendBody: true`: thân màn chạy tới
/// đáy, danh sách tự đệm đáy bằng [contentBottomPadding].
class WebTuiFloatingTabBar extends StatelessWidget {
  const WebTuiFloatingTabBar({
    required this.selectedIndex,
    required this.onSelected,
    this.badges = const {},
    super.key,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final Map<int, int> badges;

  /// Khoảng dưới thanh: vùng an toàn đáy (iPhone bớt phần thừa trên thanh
  /// home), tối thiểu [WebTuiBottomTabTokens.margin].
  static double bottomGap(BuildContext context) =>
      webTuiBottomInset(context, minimum: WebTuiBottomTabTokens.margin);

  /// Đệm đáy cho danh sách trong thân [WebTuiMobileScaffold] để mục cuối cuộn
  /// lên được trên thanh nổi. Trong thân, Scaffold (`extendBody`) đã đặt
  /// `MediaQuery.padding.bottom` bằng chiều cao thanh chiếm (chiều cao thanh +
  /// vùng an toàn đáy, xem [WebTuiBottomTabTokens.reservedHeight]); màn mở
  /// riêng ngoài thanh tab thì chỉ là vùng an toàn đáy.
  static double contentBottomPadding(BuildContext context) =>
      MediaQuery.paddingOf(context).bottom;

  @override
  Widget build(BuildContext context) {
    final palette = _TabBarPalette.of(context);
    final radius = BorderRadius.circular(WebTuiBottomTabTokens.radius);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        WebTuiBottomTabTokens.margin,
        WebTuiBottomTabTokens.topGap,
        WebTuiBottomTabTokens.margin,
        bottomGap(context),
      ),
      child: DecoratedBox(
        key: const ValueKey('floating-tab-bar-pill'),
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: [
            BoxShadow(
              color: palette.shadow,
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: WebTuiBottomTabTokens.blurSigma,
              sigmaY: WebTuiBottomTabTokens.blurSigma,
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: palette.background,
                borderRadius: radius,
                border: Border.all(color: palette.border, width: 0.8),
              ),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Row(
                  children: [
                    for (var index = 0; index < _tabs.length; index++)
                      Expanded(
                        child: _FloatingTabItem(
                          spec: _tabs[index],
                          selected: index == selectedIndex,
                          badge: badges[index] ?? 0,
                          palette: palette,
                          onTap: () => onSelected(index),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FloatingTabItem extends StatelessWidget {
  const _FloatingTabItem({
    required this.spec,
    required this.selected,
    required this.palette,
    required this.onTap,
    this.badge = 0,
  });

  final _TabSpec spec;
  final bool selected;
  final int badge;
  final _TabBarPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? palette.selected : palette.unselected;
    final radius = BorderRadius.circular(WebTuiBottomTabTokens.radius - 4);
    return Semantics(
      button: true,
      selected: selected,
      label: spec.label,
      excludeSemantics: true,
      child: InkWell(
        key: ValueKey('tab-${spec.label}'),
        onTap: onTap,
        borderRadius: radius,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          // Vùng bấm cao 54 (≥ 44), rộng ~1/4 thanh.
          constraints: const BoxConstraints(
            minHeight: WebTuiBottomTabTokens.height - 8,
          ),
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
          decoration: BoxDecoration(
            color: selected ? palette.selectedFill : Colors.transparent,
            borderRadius: radius,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    spec.icon,
                    size: WebTuiBottomTabTokens.iconSize,
                    color: color,
                  ),
                  if (badge > 0)
                    Positioned(
                      left: WebTuiBottomTabTokens.iconSize - 8,
                      top: -7,
                      child: _TabBadge(count: badge),
                    ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                spec.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  height: 1.2,
                  color: color,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Số chưa đọc màu đỏ ở góc trên phải biểu tượng tab.
class _TabBadge extends StatelessWidget {
  const _TabBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final label = count > 99 ? '99+' : '$count';
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      key: const ValueKey('tab-badge'),
      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFE5484D),
        borderRadius: BorderRadius.circular(9),
        // Viền cùng màu nền thanh để số tách khỏi biểu tượng.
        border: Border.all(
          color: dark ? const Color(0xFF1F2329) : WebTuiColors.surface,
          width: 1.5,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        maxLines: 1,
        softWrap: false,
        style: const TextStyle(
          fontSize: 11,
          height: 1.1,
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

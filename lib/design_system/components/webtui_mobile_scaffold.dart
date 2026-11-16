import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import '../icons/webtui_icons.dart';
import '../tokens/webtui_colors.dart';
import '../tokens/webtui_density.dart';
import '../tokens/webtui_spacing.dart';
import '../tokens/webtui_typography.dart';

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
      // Thanh tab nổi như viên thuốc: nội dung chạy xuống phía sau, Scaffold
      // tự cộng chiều cao thanh vào MediaQuery.padding.bottom của thân.
      extendBody: true,
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
  final String Function(AppStrings strings) label;
}

final _tabs = [
  _TabSpec(WebTuiIcons.messages, (s) => s.tabMessages),
  _TabSpec(WebTuiIcons.friends, (s) => s.tabFriends),
  _TabSpec(WebTuiIcons.work, (s) => s.tabWork),
  _TabSpec(WebTuiIcons.settings, (s) => s.tabSettings),
];

/// Thanh tab nổi dạng viên thuốc kiểu kính mờ: cách mép dưới, bo tròn, viền
/// mảnh, bóng nhẹ. Đặt làm `bottomNavigationBar` của Scaffold có
/// `extendBody: true`: nội dung cuộn được xuống phía sau thanh, còn phần cuối
/// danh sách nhận thêm đệm đáy từ `MediaQuery.padding.bottom`.
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final radius = BorderRadius.circular(WebTuiBottomTabTokens.height);
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: WebTuiBottomTabTokens.margin),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          WebTuiBottomTabTokens.margin,
          WebTuiSpacing.xs,
          WebTuiBottomTabTokens.margin,
          0,
        ),
        child: DecoratedBox(
          // Bóng nằm ngoài lớp cắt để không bị ClipRRect xén mất.
          decoration: BoxDecoration(
            borderRadius: radius,
            boxShadow: [
              BoxShadow(
                // Nền sáng: bóng rất nhẹ, không thành vệt xám dưới viên thuốc.
                color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.07),
                blurRadius: isDark ? 18 : 22,
                offset: Offset(0, isDark ? 6 : 3),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: isDark ? _pillDark : _pillLight,
                  borderRadius: radius,
                  border: Border.all(
                    color: isDark ? _pillBorderDark : _pillBorderLight,
                  ),
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
      ),
    );
  }
}

const _pillDark = Color(0xE61C1C1E);
const _pillLight = Color(0xE6FFFFFF);
const _pillBorderDark = Color(0x1FFFFFFF);
const _pillBorderLight = Color(0x14000000);
const _selectedBgDark = Color(0xFF2C2C2E);
const _selectedBgLight = Color(0xFFE8F2FF);
// Xám nhãn chưa chọn: tương phản trên nền viên thuốc ≥ 4.5:1 ở cả hai chế độ.
const _idleDark = Color(0xFFA1A1A8);
const _idleLight = Color(0xFF5B6270);
// Nhãn đang chọn ở nền sáng dùng xanh đậm hơn một bậc để đủ tương phản.
const _selectedFgLight = Color(0xFF0561C7);
const _tabAnimation = Duration(milliseconds: 150);

class _FloatingTabItem extends StatelessWidget {
  const _FloatingTabItem({
    required this.spec,
    required this.selected,
    required this.onTap,
    this.badge = 0,
  });

  final _TabSpec spec;
  final bool selected;
  final int badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeColor = isDark ? scheme.primary : _selectedFgLight;
    final color = selected ? activeColor : (isDark ? _idleDark : _idleLight);
    final label = spec.label(AppStrings.of(context));
    // Không dùng InkWell: không splash / highlight / hover đọng lại. Nút chỉ
    // đổi màu theo `selected`.
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        key: ValueKey('tab-${spec.label(const AppStringsVi())}'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: _tabAnimation,
          constraints: const BoxConstraints(
            minHeight: WebTuiBottomTabTokens.height - 8,
          ),
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
          decoration: BoxDecoration(
            color: selected
                ? (isDark ? _selectedBgDark : _selectedBgLight)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(WebTuiBottomTabTokens.height),
          ),
          child: TweenAnimationBuilder<Color?>(
            tween: ColorTween(end: color),
            duration: _tabAnimation,
            builder: (context, tint, _) => Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(
                      spec.icon,
                      size: WebTuiBottomTabTokens.iconSize,
                      color: tint,
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
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.2,
                    color: tint,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
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

/// Số chưa đọc màu đỏ ở góc biểu tượng tab.
class _TabBadge extends StatelessWidget {
  const _TabBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final label = count > 99 ? '99+' : '$count';
    return Container(
      key: const ValueKey('tab-badge'),
      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFE5484D),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: WebTuiColors.surface, width: 1.5),
      ),
      child: Center(
        widthFactor: 1,
        heightFactor: 1,
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
      ),
    );
  }
}

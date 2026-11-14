import 'package:flutter/material.dart';

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
      body: SafeArea(top: !showAppBar, child: body),
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

/// Thanh tab nổi dạng viên thuốc: cách mép dưới, bo tròn, đổ bóng nhẹ. Đặt làm
/// `bottomNavigationBar` nên phần thân luôn kết thúc phía trên thanh (không bị
/// che), kể cả vùng an toàn dưới cùng.
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
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
          decoration: BoxDecoration(
            color: scheme.surface.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(WebTuiBottomTabTokens.height),
            border: Border.all(color: scheme.outlineVariant),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.14),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
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
    );
  }
}

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
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;
    return Semantics(
      button: true,
      selected: selected,
      label: spec.label,
      excludeSemantics: true,
      child: InkWell(
        key: ValueKey('tab-${spec.label}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(WebTuiBottomTabTokens.height),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          constraints: const BoxConstraints(
            minHeight: WebTuiBottomTabTokens.height - 8,
          ),
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
          decoration: BoxDecoration(
            color: selected ? WebTuiColors.primarySoft : Colors.transparent,
            borderRadius: BorderRadius.circular(WebTuiBottomTabTokens.height),
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

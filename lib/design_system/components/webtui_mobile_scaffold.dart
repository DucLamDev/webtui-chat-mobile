import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

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
    super.key,
  });

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
      ),
    );
  }
}

class _TabSpec {
  const _TabSpec(this.icon, this.selectedIcon, this.label);

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

const _tabs = [
  _TabSpec(
    CupertinoIcons.chat_bubble_2,
    CupertinoIcons.chat_bubble_2_fill,
    'Tin nhắn',
  ),
  _TabSpec(CupertinoIcons.person_2, CupertinoIcons.person_2_fill, 'Bạn bè'),
  _TabSpec(
    CupertinoIcons.briefcase,
    CupertinoIcons.briefcase_fill,
    'Công việc',
  ),
  _TabSpec(CupertinoIcons.gear, CupertinoIcons.gear_solid, 'Cài đặt'),
];

/// Thanh tab nổi dạng viên thuốc: cách mép dưới, bo tròn, đổ bóng nhẹ. Đặt làm
/// `bottomNavigationBar` nên phần thân luôn kết thúc phía trên thanh (không bị
/// che), kể cả vùng an toàn dưới cùng.
class WebTuiFloatingTabBar extends StatelessWidget {
  const WebTuiFloatingTabBar({
    required this.selectedIndex,
    required this.onSelected,
    super.key,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

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
  });

  final _TabSpec spec;
  final bool selected;
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
            color: selected
                ? scheme.primary.withValues(alpha: 0.14)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(WebTuiBottomTabTokens.height),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                selected ? spec.selectedIcon : spec.icon,
                size: WebTuiBottomTabTokens.iconSize,
                color: color,
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

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../tokens/webtui_colors.dart';
import '../tokens/webtui_density.dart';
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
    super.key,
  });

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
      appBar: AppBar(
        toolbarHeight: 54,
        centerTitle: false,
        leading: leading,
        leadingWidth: leading == null ? 0 : 46,
        surfaceTintColor: Colors.transparent,
        shape: Border(
          bottom: BorderSide(color: WebTuiColors.border.withValues(alpha: 0.7)),
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
      body: SafeArea(top: false, child: body),
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: NavigationBar(
        height: WebTuiBottomTabTokens.height,
        selectedIndex: selectedTab,
        onDestinationSelected: onTabSelected,
        destinations: const [
          NavigationDestination(
            icon: Icon(CupertinoIcons.chat_bubble_2),
            selectedIcon: Icon(CupertinoIcons.chat_bubble_2_fill),
            label: 'Tin nhắn',
          ),
          NavigationDestination(
            icon: Icon(CupertinoIcons.person_2),
            selectedIcon: Icon(CupertinoIcons.person_2_fill),
            label: 'Bạn bè',
          ),
          NavigationDestination(
            icon: Icon(CupertinoIcons.number),
            selectedIcon: Icon(CupertinoIcons.number_circle_fill),
            label: 'Kênh',
          ),
          NavigationDestination(
            icon: Icon(CupertinoIcons.briefcase),
            selectedIcon: Icon(CupertinoIcons.briefcase_fill),
            label: 'Nghiệp vụ',
          ),
          NavigationDestination(
            icon: Icon(CupertinoIcons.gear),
            selectedIcon: Icon(CupertinoIcons.gear_solid),
            label: 'Cài đặt',
          ),
        ],
      ),
    );
  }
}

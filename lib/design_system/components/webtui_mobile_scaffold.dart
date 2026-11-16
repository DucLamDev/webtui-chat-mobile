import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
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
      // Màn tab liền mạch: nền trang (trắng ở nền sáng), không nền xám sau khối.
      backgroundColor: WebTuiColors.page,
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
  const _TabSpec(this.icon, this.activeIcon, this.label);

  final IconData icon;

  /// Dạng đặc khi tab đang chọn (kiểu Zalo).
  final IconData activeIcon;

  /// Tên tab theo ngôn ngữ đang chọn (Tiếng Việt / English).
  final String Function(AppStrings strings) label;
}

final _tabs = [
  _TabSpec(
    WebTuiIcons.messages,
    WebTuiIcons.messagesActive,
    (s) => s.tabMessages,
  ),
  _TabSpec(WebTuiIcons.friends, WebTuiIcons.friendsActive, (s) => s.tabFriends),
  _TabSpec(WebTuiIcons.work, WebTuiIcons.workActive, (s) => s.tabWork),
  _TabSpec(
    WebTuiIcons.settings,
    WebTuiIcons.settingsActive,
    (s) => s.tabSettings,
  ),
];

const _tabAnimation = Duration(milliseconds: 180);

/// Thanh tab dính đáy kiểu Zalo / Telegram: tràn mép, nền kính mờ, đường kẻ
/// mảnh phía trên. Mục chưa chọn là biểu tượng nét màu xám; mục đang chọn là
/// biểu tượng đặc + chữ màu nhấn, không có nền bao quanh.
///
/// Dùng trong [WebTuiMobileScaffold] với `extendBody: true`: thân màn chạy tới
/// đáy (nội dung cuộn ra sau lớp kính mờ), danh sách tự đệm đáy bằng
/// [contentBottomPadding].
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
  /// home).
  static double bottomGap(BuildContext context) =>
      webTuiBottomInset(context, minimum: WebTuiBottomTabTokens.margin);

  /// Đệm đáy cho danh sách trong thân [WebTuiMobileScaffold] để mục cuối cuộn
  /// lên được trên thanh tab. Trong thân, Scaffold (`extendBody`) đã đặt
  /// `MediaQuery.padding.bottom` bằng chiều cao thanh chiếm (chiều cao thanh +
  /// vùng an toàn đáy, xem [WebTuiBottomTabTokens.reservedHeight]); màn mở
  /// riêng ngoài thanh tab thì chỉ là vùng an toàn đáy.
  static double contentBottomPadding(BuildContext context) =>
      MediaQuery.paddingOf(context).bottom;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: WebTuiBottomTabTokens.blurSigma,
          sigmaY: WebTuiBottomTabTokens.blurSigma,
        ),
        child: DecoratedBox(
          key: const ValueKey('bottom-tab-bar'),
          decoration: BoxDecoration(
            color: WebTuiColors.page.withValues(alpha: 0.86),
            border: Border(
              top: BorderSide(
                color: dark
                    ? Colors.white.withValues(alpha: 0.08)
                    : WebTuiColors.textPrimary.withValues(alpha: 0.12),
                width: 0.5,
              ),
            ),
          ),
          child: Padding(
            padding: EdgeInsets.only(bottom: bottomGap(context)),
            child: SizedBox(
              height: WebTuiBottomTabTokens.height,
              child: Row(
                children: [
                  for (var index = 0; index < _tabs.length; index++)
                    Expanded(
                      child: _TabItem(
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
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({
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
    final color = selected ? WebTuiColors.primary : WebTuiColors.textMuted;
    final label = spec.label(AppStrings.of(context));
    // Không dùng InkWell: không splash / highlight đọng lại ở tab cũ; nút chỉ
    // đổi biểu tượng (nét ↔ đặc) và màu theo `selected`.
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        // Khoá theo tên tiếng Việt để test / mã gọi tìm được ở mọi ngôn ngữ.
        key: ValueKey('tab-${spec.label(const AppStringsVi())}'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: TweenAnimationBuilder<Color?>(
          tween: ColorTween(end: color),
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : _tabAnimation,
          builder: (context, tint, _) => Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    selected ? spec.activeIcon : spec.icon,
                    size: WebTuiBottomTabTokens.iconSize,
                    color: tint,
                  ),
                  if (badge > 0)
                    Positioned(
                      left: WebTuiBottomTabTokens.iconSize - 10,
                      top: -4,
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
                  fontFamily: WebTuiTypography.fontFamily,
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
    return Container(
      key: const ValueKey('tab-badge'),
      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: WebTuiColors.badge,
        borderRadius: BorderRadius.circular(9),
        // Viền cùng màu nền thanh để số tách khỏi biểu tượng.
        border: Border.all(color: WebTuiColors.page, width: 1.5),
      ),
      // Center co theo chữ: số là viên tròn 18px giãn ngang theo số, không bị
      // kéo dài theo khung cha.
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

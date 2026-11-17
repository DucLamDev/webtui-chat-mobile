import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
      // Thanh tab là viên thuốc nổi đè lên thân: nội dung cuộn ra phía sau lớp
      // kính mờ và chạy cả hai bên / phía dưới viên thuốc. Thân không tự chừa
      // đáy; Scaffold đặt `MediaQuery.padding.bottom` của thân bằng chiều cao
      // thanh chiếm (khoảng trên + viên thuốc + khoảng dưới), danh sách trong tab
      // đệm đáy theo [WebTuiFloatingTabBar.contentBottomPadding].
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

/// Nền mục đang chọn trượt sang tab mới.
const _selectionAnimation = Duration(milliseconds: 280);

/// Thanh tab nổi kiểu Telegram: viên thuốc kính mờ cách hai mép và đáy màn
/// hình, nội dung cuộn ra phía sau (mờ) và chạy hai bên. Mục đang chọn có nền
/// viên thuốc nhỏ trượt theo, biểu tượng đặc + chữ màu nhấn; mục khác là biểu
/// tượng nét màu chữ chính. Số chưa đọc là viên đỏ ở góc biểu tượng.
///
/// Dùng trong [WebTuiMobileScaffold] với `extendBody: true`: thân màn chạy tới
/// đáy, danh sách tự đệm đáy bằng [contentBottomPadding]. Vùng trong suốt quanh
/// viên thuốc không nhận chạm (chạm xuyên xuống nội dung phía sau).
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

  /// Khoảng dưới viên thuốc: vùng an toàn đáy (iPhone bớt phần thừa trên thanh
  /// home), ít nhất [WebTuiBottomTabTokens.margin] để viên thuốc luôn nổi.
  static double bottomGap(BuildContext context) =>
      webTuiBottomInset(context, minimum: WebTuiBottomTabTokens.margin);

  /// Đệm đáy cho danh sách trong thân [WebTuiMobileScaffold] để mục cuối cuộn
  /// lên được trên viên thuốc. Trong thân, Scaffold (`extendBody`) đã đặt
  /// `MediaQuery.padding.bottom` bằng chiều cao thanh chiếm (xem
  /// [WebTuiBottomTabTokens.reservedHeight]); màn mở riêng ngoài thanh tab thì
  /// chỉ là vùng an toàn đáy.
  static double contentBottomPadding(BuildContext context) =>
      MediaQuery.paddingOf(context).bottom;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    const radius = BorderRadius.all(
      Radius.circular(WebTuiBottomTabTokens.height / 2),
    );
    const inset = WebTuiBottomTabTokens.selectionInset;
    final count = _tabs.length;
    final selected = selectedIndex.clamp(0, count - 1);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        WebTuiBottomTabTokens.sideMargin,
        WebTuiBottomTabTokens.topGap,
        WebTuiBottomTabTokens.sideMargin,
        bottomGap(context),
      ),
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: WebTuiBottomTabTokens.maxWidth,
          ),
          // Bóng nằm ngoài lớp cắt bo tròn (lớp cắt sẽ cắt mất bóng).
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: radius,
              boxShadow: _glassShadows(dark),
            ),
            child: ClipRRect(
              borderRadius: radius,
              child: BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: WebTuiBottomTabTokens.blurSigma,
                  sigmaY: WebTuiBottomTabTokens.blurSigma,
                ),
                child: CustomPaint(
                  foregroundPainter: _GlassRimPainter(dark: dark),
                  child: DecoratedBox(
                    key: const ValueKey('bottom-tab-bar'),
                    decoration: BoxDecoration(
                      // Kính trong kiểu Telegram: thấy màu nội dung phía sau
                      // (đã làm mờ), chữ vẫn đọc rõ. Nền tối: kính sáng hơn nền
                      // trang một bậc để viên thuốc nổi khỏi nền.
                      color: dark
                          ? Color.alphaBlend(
                              Colors.white.withValues(alpha: 0.08),
                              WebTuiColors.page,
                            ).withValues(alpha: 0.7)
                          : WebTuiColors.page.withValues(alpha: 0.62),
                      borderRadius: radius,
                    ),
                    // Chữ hệ thống rất lớn: giữ nhãn trong viên thuốc (như
                    // Telegram), các màn khác vẫn phóng chữ bình thường.
                    child: MediaQuery.withClampedTextScaling(
                      maxScaleFactor: 1.3,
                      child: SizedBox(
                        height: WebTuiBottomTabTokens.height,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(inset),
                              child: AnimatedAlign(
                                alignment: Alignment(
                                  count == 1
                                      ? 0
                                      : -1 + 2 * selected / (count - 1),
                                  0,
                                ),
                                duration: reduceMotion
                                    ? Duration.zero
                                    : _selectionAnimation,
                                curve: Curves.easeOutCubic,
                                child: FractionallySizedBox(
                                  widthFactor: 1 / count,
                                  heightFactor: 1,
                                  child: DecoratedBox(
                                    key: const ValueKey('tab-selection-pill'),
                                    decoration: BoxDecoration(
                                      color: dark
                                          ? Colors.black.withValues(alpha: 0.34)
                                          : WebTuiColors.textPrimary.withValues(
                                              alpha: 0.06,
                                            ),
                                      borderRadius: const BorderRadius.all(
                                        Radius.circular(
                                          WebTuiBottomTabTokens.height / 2 -
                                              inset,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            // Hàng mục thụt vào đúng như nền mục chọn để tâm nền
                            // trùng tâm biểu tượng ở mọi tab.
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: inset,
                              ),
                              child: Row(
                                children: [
                                  for (var index = 0; index < count; index++)
                                    Expanded(
                                      child: _TabItem(
                                        spec: _tabs[index],
                                        selected: index == selected,
                                        badge: badges[index] ?? 0,
                                        onTap: () {
                                          if (index != selectedIndex) {
                                            HapticFeedback.selectionClick();
                                          }
                                          onSelected(index);
                                        },
                                      ),
                                    ),
                                ],
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
          ),
        ),
      ),
    );
  }
}

/// Bóng mềm dưới viên thuốc: nền sáng nhạt (thêm lớp sát mép cho rõ khối),
/// nền tối đậm hơn để tách khỏi nền.
List<BoxShadow> _glassShadows(bool dark) => dark
    ? const [
        BoxShadow(
          color: Color(0x73000000),
          blurRadius: 28,
          offset: Offset(0, 10),
        ),
      ]
    : const [
        BoxShadow(
          color: Color(0x1F0F1A2E),
          blurRadius: 28,
          offset: Offset(0, 10),
        ),
        BoxShadow(
          color: Color(0x120F1A2E),
          blurRadius: 4,
          offset: Offset(0, 1),
        ),
      ];

/// Viền mảnh của lớp kính: sáng ở mép trên (ánh sáng chiếu xuống), nhạt dần
/// về mép dưới, giống viền kính của Telegram / iOS.
class _GlassRimPainter extends CustomPainter {
  const _GlassRimPainter({required this.dark});

  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(
      rect.deflate(0.5),
      Radius.circular(size.height / 2),
    );
    final colors = dark
        ? [
            Colors.white.withValues(alpha: 0.18),
            Colors.white.withValues(alpha: 0.05),
          ]
        : [
            Colors.white.withValues(alpha: 0.95),
            WebTuiColors.textPrimary.withValues(alpha: 0.10),
          ];
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: colors,
      ).createShader(rect);
    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(_GlassRimPainter old) => old.dark != dark;
}

class _TabItem extends StatefulWidget {
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
  State<_TabItem> createState() => _TabItemState();
}

class _TabItemState extends State<_TabItem> {
  /// Đang nhấn: biểu tượng thu nhỏ một chút (phản hồi chạm như Telegram).
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final spec = widget.spec;
    final selected = widget.selected;
    final color = selected ? WebTuiColors.primary : WebTuiColors.textPrimary;
    final label = spec.label(AppStrings.of(context));
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    // Không dùng InkWell: không splash / highlight đọng lại ở tab cũ; mục chọn
    // thể hiện bằng nền viên thuốc trượt, biểu tượng đặc và màu nhấn.
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      onTap: widget.onTap,
      excludeSemantics: true,
      child: GestureDetector(
        // Khoá theo tên tiếng Việt để test / mã gọi tìm được ở mọi ngôn ngữ.
        key: ValueKey('tab-${spec.label(const AppStringsVi())}'),
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _setPressed(true),
        onTapCancel: () => _setPressed(false),
        onTapUp: (_) => _setPressed(false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _pressed && !reduceMotion ? 0.9 : 1,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: TweenAnimationBuilder<Color?>(
            tween: ColorTween(end: color),
            duration: reduceMotion ? Duration.zero : _tabAnimation,
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
                    if (widget.badge > 0)
                      Positioned(
                        left: WebTuiBottomTabTokens.iconSize - 9,
                        top: -5,
                        child: _TabBadge(count: widget.badge),
                      ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: WebTuiTypography.fontFamily,
                    fontSize: 10.5,
                    height: 1.2,
                    letterSpacing: 0.1,
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

import 'package:flutter/material.dart';

import '../../../../design_system/components/webtui_components.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../../../../l10n/app_strings.dart';

/// Một tab của thanh gạch chân Bạn bè.
class ContactsUnderlineTab {
  const ContactsUnderlineTab({
    required this.key,
    required this.label,
    required this.count,
  });

  final Key key;
  final String label;
  final int count;
}

/// Thanh tab gạch chân kiểu Zalo: chữ đậm, gạch primary dưới tab chọn, số
/// đếm nhỏ cạnh chữ. Mỗi tab cao 44.
class ContactsUnderlineTabs extends StatelessWidget {
  const ContactsUnderlineTabs({
    required this.tabs,
    required this.selectedIndex,
    required this.onSelected,
    this.semanticLabel,
    super.key,
  });

  static const double height = 44;

  final List<ContactsUnderlineTab> tabs;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: semanticLabel,
      child: Row(
        children: [
          for (var i = 0; i < tabs.length; i++)
            Expanded(
              child: _UnderlineTab(
                key: tabs[i].key,
                tab: tabs[i],
                selected: i == selectedIndex,
                onTap: () => onSelected(i),
              ),
            ),
        ],
      ),
    );
  }
}

class _UnderlineTab extends StatelessWidget {
  const _UnderlineTab({
    required this.tab,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final ContactsUnderlineTab tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? WebTuiColors.textPrimary : WebTuiColors.textMuted;
    return Semantics(
      button: true,
      selected: selected,
      label: '${tab.label} ${tab.count}',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      tab.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: WebTuiTypography.titleMedium.copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '${tab.count}',
                    style: WebTuiTypography.bodySmall.copyWith(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: WebTuiColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              height: 2.5,
              margin: const EdgeInsets.symmetric(horizontal: 18),
              decoration: BoxDecoration(
                color: selected ? WebTuiColors.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Đầu danh bạ dính trên cùng: ô tìm ngay dưới thanh trạng thái + tab gạch chân.
class ContactsPinnedHeader extends SliverPersistentHeaderDelegate {
  ContactsPinnedHeader({required this.search, required this.tabs});

  static const double _searchHeight = 40;
  static const double extent =
      4 + _searchHeight + 6 + ContactsUnderlineTabs.height + 1;

  final Widget search;
  final Widget tabs;

  @override
  double get minExtent => extent;

  @override
  double get maxExtent => extent;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return ColoredBox(
      color: WebTuiColors.page,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              WebTuiSpacing.lg,
              4,
              WebTuiSpacing.lg,
              6,
            ),
            child: SizedBox(height: _searchHeight, child: search),
          ),
          SizedBox(height: ContactsUnderlineTabs.height, child: tabs),
          const WebTuiHairline(),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(covariant ContactsPinnedHeader oldDelegate) =>
      oldDelegate.search != search || oldDelegate.tabs != tabs;
}

/// Tiêu đề nhóm chữ cái (dính khi cuộn), nền trùng nền danh sách.
class ContactLetterHeader extends SliverPersistentHeaderDelegate {
  ContactLetterHeader(this.letter);

  static const double extent = 28;

  final String letter;

  @override
  double get minExtent => extent;

  @override
  double get maxExtent => extent;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return ColoredBox(
      color: WebTuiColors.page,
      child: Semantics(
        header: true,
        child: Align(
          alignment: Alignment.bottomLeft,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(WebTuiSpacing.lg, 0, 16, 4),
            child: Text(
              letter,
              key: ValueKey('contact-letter-$letter'),
              style: WebTuiTypography.bodySmall.copyWith(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: WebTuiColors.textMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant ContactLetterHeader oldDelegate) =>
      oldDelegate.letter != letter;
}

/// Hai nút cuối dòng đồng nghiệp: gọi thoại và gọi video (vùng bấm 44).
class ContactCallButtons extends StatelessWidget {
  const ContactCallButtons({
    required this.onAudio,
    required this.onVideo,
    super.key,
  });

  final VoidCallback onAudio;
  final VoidCallback onVideo;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _CallButton(
          key: const ValueKey('contact-call-audio'),
          icon: Icons.call_outlined,
          tooltip: tr('Gọi thoại', 'Voice call'),
          onPressed: onAudio,
        ),
        _CallButton(
          key: const ValueKey('contact-call-video'),
          icon: Icons.videocam_outlined,
          tooltip: tr('Gọi video', 'Video call'),
          onPressed: onVideo,
        ),
      ],
    );
  }
}

class _CallButton extends StatelessWidget {
  const _CallButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    super.key,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: 22, color: WebTuiColors.textMuted),
      constraints: const BoxConstraints.tightFor(width: 44, height: 44),
      padding: EdgeInsets.zero,
      splashRadius: 22,
    );
  }
}

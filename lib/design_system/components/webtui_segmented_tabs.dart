import 'package:flutter/material.dart';

import '../tokens/webtui_colors.dart';
import '../tokens/webtui_density.dart';
import '../tokens/webtui_radii.dart';
import '../tokens/webtui_spacing.dart';
import '../tokens/webtui_typography.dart';

class WebTuiSegmentedTabs extends StatelessWidget {
  const WebTuiSegmentedTabs({
    required this.tabs,
    required this.selectedIndex,
    required this.onChanged,
    super.key,
  });

  final List<String> tabs;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: WebTuiSegmentedControlTokens.height,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: WebTuiColors.backgroundMuted,
        borderRadius: BorderRadius.circular(WebTuiRadii.segmented),
        border: Border.all(color: WebTuiColors.border.withValues(alpha: 0.55)),
      ),
      child: tabs.length <= 3
          ? Row(
              children: [
                for (var index = 0; index < tabs.length; index++)
                  Expanded(
                    child: _SegmentButton(
                      label: tabs[index],
                      selected: selectedIndex == index,
                      onTap: () => onChanged(index),
                    ),
                  ),
              ],
            )
          : ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: tabs.length,
              separatorBuilder: (_, _) => const SizedBox(width: 4),
              itemBuilder: (context, index) {
                return SizedBox(
                  width: 104,
                  child: _SegmentButton(
                    label: tabs[index],
                    selected: selectedIndex == index,
                    onTap: () => onChanged(index),
                  ),
                );
              },
            ),
    );
  }
}

class _SegmentButton extends StatelessWidget {
  const _SegmentButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(WebTuiRadii.sm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(WebTuiRadii.sm),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: selected ? WebTuiColors.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(WebTuiRadii.sm),
            border: selected
                ? Border.all(
                    color: WebTuiColors.primary.withValues(alpha: 0.12),
                  )
                : null,
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: WebTuiColors.primary.withValues(alpha: 0.08),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: WebTuiSpacing.xs),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: WebTuiTypography.bodySmall.copyWith(
                  color: selected
                      ? WebTuiColors.primary
                      : WebTuiColors.textSecondary,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

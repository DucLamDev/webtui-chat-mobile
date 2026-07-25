import 'package:flutter/material.dart';

import '../tokens/webtui_colors.dart';
import '../tokens/webtui_density.dart';
import '../tokens/webtui_radii.dart';
import '../tokens/webtui_spacing.dart';
import '../tokens/webtui_typography.dart';

class WebTuiSettingRow extends StatelessWidget {
  const WebTuiSettingRow({
    required this.title,
    required this.icon,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.destructive = false,
    super.key,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? WebTuiColors.danger : WebTuiColors.textPrimary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: subtitle == null
              ? WebTuiListDensity.compactItemHeight
              : WebTuiListDensity.conversationItemHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: WebTuiSpacing.lg),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: destructive
                        ? WebTuiColors.danger.withValues(alpha: 0.1)
                        : WebTuiColors.primarySoft,
                    borderRadius: BorderRadius.circular(WebTuiRadii.sm),
                  ),
                  child: Icon(
                    icon,
                    size: 19,
                    color: destructive
                        ? WebTuiColors.danger
                        : WebTuiColors.primary,
                  ),
                ),
                const SizedBox(width: WebTuiSpacing.md),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: WebTuiTypography.bodyMedium.copyWith(
                          color: color,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: WebTuiSpacing.xs),
                        Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: WebTuiTypography.bodySmall.copyWith(
                            color: WebTuiColors.textMuted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: WebTuiSpacing.sm),
                trailing ??
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: WebTuiColors.textMuted,
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class WebTuiToggle extends StatelessWidget {
  const WebTuiToggle({required this.value, required this.onChanged, super.key});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Switch(
      value: value,
      onChanged: onChanged,
      activeThumbColor: WebTuiColors.textOnPrimary,
      activeTrackColor: WebTuiColors.primary,
      inactiveThumbColor: WebTuiColors.surface,
      inactiveTrackColor: WebTuiColors.border,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}

class WebTuiSliderRow extends StatelessWidget {
  const WebTuiSliderRow({
    required this.icon,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final IconData icon;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: WebTuiSpacing.lg),
        child: Row(
          children: [
            Icon(icon, size: 19, color: WebTuiColors.textMuted),
            const SizedBox(width: WebTuiSpacing.md),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 7,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 14,
                  ),
                ),
                child: Slider(
                  value: value,
                  onChanged: onChanged,
                  activeColor: WebTuiColors.primary,
                  inactiveColor: WebTuiColors.border,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

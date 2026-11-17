import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../icons/webtui_icons.dart';
import '../tokens/webtui_colors.dart';
import '../tokens/webtui_spacing.dart';
import '../tokens/webtui_typography.dart';

/// Lề trái + biểu tượng + khoảng của dòng cài đặt: đường kẻ thụt tới chữ.
const double webTuiSettingDividerIndent = 16 + 24 + 14;

/// Dòng cài đặt liền mạch: biểu tượng trơn 24px (không ô nền), chữ 16px, giá
/// trị (nếu có) màu xám bên phải rồi mũi tên; cả dòng bấm được.
class WebTuiSettingRow extends StatelessWidget {
  const WebTuiSettingRow({
    required this.title,
    required this.icon,
    this.subtitle,
    this.value,
    this.trailing,
    this.onTap,
    this.destructive = false,
    this.showChevron = true,
    super.key,
  });

  final String title;
  final String? subtitle;

  /// Giá trị hiện tại (vd tên workspace, "Theo máy") nằm trước mũi tên.
  final String? value;
  final IconData icon;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool destructive;

  /// Dòng mở màn khác có mũi tên; dòng hành động (Đăng xuất) thì không.
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? WebTuiColors.danger : WebTuiColors.textPrimary;
    final iconColor = destructive
        ? WebTuiColors.danger
        : WebTuiColors.textSecondary;

    return Material(
      color: WebTuiColors.page,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Padding(
            padding: const EdgeInsets.only(left: WebTuiSpacing.lg),
            child: Row(
              children: [
                Icon(icon, size: 24, color: iconColor),
                const SizedBox(width: 14),
                Expanded(
                  child: Padding(
                    // Dòng có công tắc / nút cuối: công tắc kiểu iOS cao 39 (gồm
                    // vùng bấm) nên đệm dọc nhỏ lại để dòng vẫn cao 52.
                    padding: EdgeInsets.fromLTRB(
                      0,
                      trailing == null ? 14 : 6,
                      12,
                      trailing == null ? 14 : 6,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: WebTuiTypography.bodyMedium.copyWith(
                                  color: color,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                              if (subtitle != null) ...[
                                const SizedBox(height: 2),
                                Text(
                                  subtitle!,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: WebTuiTypography.bodySmall.copyWith(
                                    fontSize: 13.5,
                                    color: WebTuiColors.textMuted,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (value != null) ...[
                          const SizedBox(width: WebTuiSpacing.sm),
                          // Giá trị chỉ chiếm phần cần (tối đa 40% màn), sát mũi tên.
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: MediaQuery.sizeOf(context).width * 0.4,
                            ),
                            child: Text(
                              value!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.right,
                              style: WebTuiTypography.bodyMedium.copyWith(
                                fontSize: 15,
                                color: WebTuiColors.textMuted,
                              ),
                            ),
                          ),
                        ],
                        if (trailing != null) ...[
                          const SizedBox(width: WebTuiSpacing.sm),
                          trailing!,
                        ] else if (showChevron && !destructive) ...[
                          const SizedBox(width: 4),
                          Icon(
                            WebTuiIcons.forward,
                            size: 18,
                            color: WebTuiColors.textMuted,
                          ),
                        ],
                      ],
                    ),
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

/// Công tắc kiểu iOS (51 × 31). Cả dòng chứa nó nên bấm được để đổi.
class WebTuiToggle extends StatelessWidget {
  const WebTuiToggle({required this.value, required this.onChanged, super.key});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return CupertinoSwitch(
      value: value,
      onChanged: onChanged,
      activeTrackColor: WebTuiColors.primaryFill,
      inactiveTrackColor: WebTuiColors.brightness == Brightness.dark
          ? const Color(0xFF2A3547)
          : const Color(0xFFE3E6EB),
    );
  }
}

/// Dòng thanh kéo kiểu iOS: biểu tượng, nhãn ngắn, rãnh mảnh 4px, nút trắng
/// có bóng.
class WebTuiSliderRow extends StatelessWidget {
  const WebTuiSliderRow({
    required this.icon,
    required this.value,
    required this.onChanged,
    this.label,
    this.divisions,
    this.onChangeEnd,
    this.semanticValue,
    super.key,
  });

  final IconData icon;
  final double value;
  final ValueChanged<double> onChanged;

  /// Nhãn ngắn trước thanh (vd "Âm lượng"); cũng là nhãn cho trình đọc màn hình.
  final String? label;

  /// Số nấc (thanh nhảy theo nấc, không hiện chấm nấc); null = kéo liền.
  final int? divisions;

  /// Gọi khi thả tay (vd phát thử âm lượng vừa chọn).
  final ValueChanged<double>? onChangeEnd;

  /// Giá trị đọc cho trình đọc màn hình (vd "100%"); mặc định là phần trăm vị
  /// trí thanh.
  final String Function(double value)? semanticValue;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: WebTuiColors.page,
      child: SizedBox(
        height: 52,
        child: Padding(
          padding: const EdgeInsets.only(left: WebTuiSpacing.lg, right: 12),
          child: Row(
            children: [
              Icon(icon, size: 24, color: WebTuiColors.textSecondary),
              const SizedBox(width: 14),
              if (label != null)
                SizedBox(
                  // Cột nhãn giãn theo cỡ chữ (Cài đặt > Cỡ chữ, chữ hệ thống):
                  // chữ to không bị cắt thành "Âm lượ…".
                  width: MediaQuery.textScalerOf(context).scale(92),
                  child: Text(
                    label!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: WebTuiTypography.bodyMedium.copyWith(
                      fontSize: 16,
                      color: WebTuiColors.textPrimary,
                    ),
                  ),
                ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 4,
                    activeTrackColor: WebTuiColors.primaryFill,
                    inactiveTrackColor: WebTuiColors.hairline,
                    thumbColor: Colors.white,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 13,
                      elevation: 2,
                      pressedElevation: 3,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 22,
                    ),
                    // Rãnh chạy sát lề phải (chỉ chừa nửa nút kéo), như iOS.
                    padding: const EdgeInsets.symmetric(horizontal: 13),
                    overlayColor: WebTuiColors.primary.withValues(alpha: 0.08),
                    trackShape: const RoundedRectSliderTrackShape(),
                    // Thanh có nấc vẫn trơn như iOS, không chấm nấc trên rãnh.
                    tickMarkShape: SliderTickMarkShape.noTickMark,
                  ),
                  child: Slider(
                    value: value.clamp(0.0, 1.0),
                    divisions: divisions,
                    onChanged: onChanged,
                    onChangeEnd: onChangeEnd,
                    semanticFormatterCallback: label == null
                        ? null
                        : (value) =>
                              '$label ${semanticValue?.call(value) ?? '${(value * 100).round()}%'}',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

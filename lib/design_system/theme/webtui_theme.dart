import 'package:flutter/material.dart';

import '../tokens/webtui_colors.dart';
import '../tokens/webtui_radii.dart';
import '../tokens/webtui_spacing.dart';
import '../tokens/webtui_typography.dart';

final class WebTuiTheme {
  const WebTuiTheme._();

  static ThemeData light() => _withPalette(Brightness.light);

  static ThemeData dark() => _withPalette(Brightness.dark);

  /// Dựng theme từ bảng màu của [brightness], rồi trả bảng màu đang áp dụng
  /// về như cũ (chỉ [WebTuiColors.apply] mới đổi bảng màu của app).
  static ThemeData _withPalette(Brightness brightness) {
    final previous = WebTuiColors.brightness;
    WebTuiColors.apply(brightness);
    try {
      return _build(brightness);
    } finally {
      WebTuiColors.apply(previous);
    }
  }

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final colorScheme = ColorScheme.fromSeed(
      seedColor: WebTuiColors.primary,
      brightness: brightness,
      primary: WebTuiColors.primary,
      surface: WebTuiColors.surface,
      // Màu "tonal" (nút FilledButton.tonal, chip...) theo xanh nhạt của app
      // thay vì xám tím Material tự sinh.
      secondaryContainer: WebTuiColors.primarySoft,
      onSecondaryContainer: WebTuiColors.primary,
      outlineVariant: WebTuiColors.border,
      onSurface: isDark ? WebTuiColors.textPrimary : null,
      onSurfaceVariant: isDark ? WebTuiColors.textSecondary : null,
    ).copyWith(surfaceTint: Colors.transparent);
    final dialogShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(WebTuiRadii.dialog),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: WebTuiColors.background,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
      textTheme: WebTuiTypography.textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: WebTuiColors.surface,
        foregroundColor: WebTuiColors.textPrimary,
        elevation: 0,
        centerTitle: false,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: WebTuiColors.primary,
        foregroundColor: WebTuiColors.textOnPrimary,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 1,
        highlightElevation: 0,
        // StadiumBorder: nút tròn (56×56) vẫn tròn, nút có chữ (.extended) thành viên thuốc. CircleBorder làm nút
        // có chữ thành hình tròn và chữ tràn ra ngoài.
        shape: const StadiumBorder(),
        extendedPadding: const EdgeInsetsDirectional.only(start: 16, end: 20),
        extendedIconLabelSpacing: 8,
        // textTheme của app không có labelLarge: lấy thẳng kiểu chữ có phông
        // WebTuiRoboto, nếu không chữ nút rơi về phông hệ thống.
        extendedTextStyle: WebTuiTypography.bodyMedium.copyWith(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
        ),
      ),
      // Hộp thoại / bảng trượt / menu: nền trắng, bo lớn, không phủ màu tím
      // của Material 3 (mặc định nền surfaceContainerHigh trông xám tím).
      dialogTheme: DialogThemeData(
        backgroundColor: WebTuiColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shadowColor: const Color(0x33172033),
        shape: dialogShape,
        insetPadding: const EdgeInsets.symmetric(
          horizontal: WebTuiSpacing.xxl,
          vertical: WebTuiSpacing.xxl,
        ),
        titleTextStyle: WebTuiTypography.titleLarge.copyWith(
          fontSize: 19,
          fontWeight: FontWeight.w800,
          color: WebTuiColors.textPrimary,
        ),
        contentTextStyle: WebTuiTypography.bodyMedium.copyWith(
          fontSize: 15,
          height: 1.45,
          color: WebTuiColors.textSecondary,
        ),
        actionsPadding: const EdgeInsets.fromLTRB(
          WebTuiSpacing.xl,
          0,
          WebTuiSpacing.xl,
          WebTuiSpacing.xl,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: WebTuiColors.surface,
        modalBackgroundColor: WebTuiColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        modalElevation: 0,
        showDragHandle: true,
        dragHandleColor: isDark
            ? const Color(0xFF475569)
            : const Color(0xFFCBD5E1),
        dragHandleSize: Size(40, 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(WebTuiRadii.sheet),
          ),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: WebTuiColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        shadowColor: const Color(0x33172033),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(WebTuiRadii.lg),
        ),
        textStyle: WebTuiTypography.bodyMedium.copyWith(
          fontSize: 15,
          color: WebTuiColors.textPrimary,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: WebTuiColors.primary,
          minimumSize: const Size(48, 44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(WebTuiRadii.md),
          ),
          textStyle: WebTuiTypography.bodyMedium.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: WebTuiColors.textPrimary,
          minimumSize: const Size(48, 46),
          side: BorderSide(color: WebTuiColors.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(WebTuiRadii.md),
          ),
          textStyle: WebTuiTypography.bodyMedium.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: WebTuiColors.border,
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: WebTuiColors.surface,
        hintStyle: WebTuiTypography.bodyMedium.copyWith(
          color: WebTuiColors.textMuted,
        ),
        labelStyle: WebTuiTypography.bodyMedium.copyWith(
          color: WebTuiColors.textSecondary,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: WebTuiSpacing.md,
          vertical: WebTuiSpacing.sm,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(WebTuiRadii.md),
          borderSide: BorderSide(color: WebTuiColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(WebTuiRadii.md),
          borderSide: BorderSide(color: WebTuiColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(WebTuiRadii.md),
          borderSide: BorderSide(color: WebTuiColors.primary, width: 1.4),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 46),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(WebTuiRadii.md),
          ),
          textStyle: WebTuiTypography.bodyMedium.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 62,
        elevation: 0,
        backgroundColor: WebTuiColors.surface,
        indicatorColor: WebTuiColors.primarySoft,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return WebTuiTypography.labelSmall.copyWith(
            color: selected ? WebTuiColors.primary : WebTuiColors.textMuted,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? WebTuiColors.primary : WebTuiColors.textMuted,
            size: 21,
          );
        }),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.selected)
                ? WebTuiColors.surface
                : WebTuiColors.backgroundMuted;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.selected)
                ? WebTuiColors.primary
                : WebTuiColors.textSecondary;
          }),
          side: const WidgetStatePropertyAll(BorderSide.none),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: WebTuiSpacing.sm),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(WebTuiRadii.segmented),
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../tokens/webtui_colors.dart';
import '../tokens/webtui_radii.dart';
import '../tokens/webtui_spacing.dart';
import '../tokens/webtui_typography.dart';

final class WebTuiTheme {
  const WebTuiTheme._();

  static ThemeData light() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: WebTuiColors.primary,
      brightness: Brightness.light,
      primary: WebTuiColors.primary,
      surface: WebTuiColors.surface,
      // Màu "tonal" (nút FilledButton.tonal, chip...) theo xanh nhạt của app
      // thay vì xám tím Material tự sinh.
      secondaryContainer: WebTuiColors.primarySoft,
      onSecondaryContainer: WebTuiColors.primary,
      outlineVariant: WebTuiColors.border,
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
      appBarTheme: const AppBarTheme(
        backgroundColor: WebTuiColors.surface,
        foregroundColor: WebTuiColors.textPrimary,
        elevation: 0,
        centerTitle: false,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: WebTuiColors.primary,
        foregroundColor: WebTuiColors.textOnPrimary,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 1,
        highlightElevation: 0,
        shape: CircleBorder(),
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
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: WebTuiColors.surface,
        modalBackgroundColor: WebTuiColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        modalElevation: 0,
        showDragHandle: true,
        dragHandleColor: Color(0xFFCBD5E1),
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
          side: const BorderSide(color: WebTuiColors.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(WebTuiRadii.md),
          ),
          textStyle: WebTuiTypography.bodyMedium.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      dividerTheme: const DividerThemeData(
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
          borderSide: const BorderSide(color: WebTuiColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(WebTuiRadii.md),
          borderSide: const BorderSide(color: WebTuiColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(WebTuiRadii.md),
          borderSide: const BorderSide(color: WebTuiColors.primary, width: 1.4),
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

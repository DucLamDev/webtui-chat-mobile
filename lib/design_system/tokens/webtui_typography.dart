import 'package:flutter/material.dart';

/// Kiểu chữ của app. Không đặt phông riêng: chữ dùng phông hệ thống như Zalo
/// trên điện thoại (iPhone: San Francisco, Android: Roboto) qua `Typography`
/// mặc định của theme, nên mọi chữ (kể cả menu, hộp thoại, nút của Material)
/// cùng một phông và chữ Việt hiển thị chuẩn của máy.
final class WebTuiTypography {
  const WebTuiTypography._();

  static const titleLarge = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    height: 1.25,
  );

  static const titleMedium = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    height: 1.3,
  );

  static const bodyMedium = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 1.35,
  );

  static const bodySmall = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.35,
  );

  static const labelSmall = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    height: 1.2,
  );

  /// Phông mã (đóng gói, OFL) cho mã, terminal, đường dẫn, mã commit. Đây là
  /// phông duy nhất app tự kèm; chữ thường vẫn theo phông hệ thống.
  static const monoFamily = 'JetBrainsMono';

  static const monoFallback = ['Menlo', 'Roboto Mono', 'Courier', 'monospace'];

  /// Chữ mã cỡ [size] (mặc định 13), không giãn chữ để cột thẳng hàng.
  static TextStyle mono({double size = 13, FontWeight? weight, Color? color}) =>
      TextStyle(
        fontFamily: monoFamily,
        fontFamilyFallback: monoFallback,
        fontSize: size,
        fontWeight: weight,
        color: color,
        letterSpacing: 0,
      );

  static const textTheme = TextTheme(
    titleLarge: titleLarge,
    titleMedium: titleMedium,
    bodyMedium: bodyMedium,
    bodySmall: bodySmall,
    labelSmall: labelSmall,
  );
}

import 'package:flutter/material.dart';

/// Bảng màu theo chế độ sáng / tối.
@immutable
final class WebTuiPalette {
  const WebTuiPalette({
    required this.primary,
    required this.primaryPressed,
    required this.primarySoft,
    required this.chatHeader,
    required this.accentGreen,
    required this.accentAmber,
    required this.danger,
    required this.background,
    required this.backgroundMuted,
    required this.chatBackground,
    required this.messageIncoming,
    required this.messageOutgoing,
    required this.messageOutgoingBorder,
    required this.surface,
    required this.surfaceElevated,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.textOnPrimary,
  });

  static const light = WebTuiPalette(
    primary: Color(0xFF0877F2),
    primaryPressed: Color(0xFF0561C7),
    primarySoft: Color(0xFFE8F2FF),
    chatHeader: Color(0xFF13A8F7),
    accentGreen: Color(0xFF21A875),
    accentAmber: Color(0xFFE2A12C),
    danger: Color(0xFFE45B5B),
    background: Color(0xFFF6F8FC),
    backgroundMuted: Color(0xFFEEF3F8),
    chatBackground: Color(0xFFE8F0F7),
    messageIncoming: Color(0xFFFFFFFF),
    messageOutgoing: Color(0xFFD9F3FF),
    messageOutgoingBorder: Color(0xFFB7DFF4),
    surface: Color(0xFFFFFFFF),
    surfaceElevated: Color(0xFFFAFCFF),
    border: Color(0xFFDDE6F1),
    textPrimary: Color(0xFF172033),
    textSecondary: Color(0xFF536074),
    textMuted: Color(0xFF8A96A8),
    textOnPrimary: Color(0xFFFFFFFF),
  );

  static const dark = WebTuiPalette(
    primary: Color(0xFF3D96FF),
    primaryPressed: Color(0xFF2B82E6),
    primarySoft: Color(0xFF14304F),
    chatHeader: Color(0xFF0E5C8C),
    accentGreen: Color(0xFF2FBF87),
    accentAmber: Color(0xFFEDB04A),
    danger: Color(0xFFF07A7A),
    background: Color(0xFF0F1623),
    backgroundMuted: Color(0xFF141D2C),
    chatBackground: Color(0xFF0B121D),
    messageIncoming: Color(0xFF1D2939),
    messageOutgoing: Color(0xFF123A57),
    messageOutgoingBorder: Color(0xFF1F5578),
    surface: Color(0xFF172131),
    surfaceElevated: Color(0xFF1D2939),
    border: Color(0xFF2A3850),
    textPrimary: Color(0xFFE6ECF5),
    textSecondary: Color(0xFFA7B3C6),
    textMuted: Color(0xFF7A879B),
    textOnPrimary: Color(0xFFFFFFFF),
  );

  final Color primary;
  final Color primaryPressed;
  final Color primarySoft;
  final Color chatHeader;
  final Color accentGreen;
  final Color accentAmber;
  final Color danger;
  final Color background;
  final Color backgroundMuted;
  final Color chatBackground;
  final Color messageIncoming;
  final Color messageOutgoing;
  final Color messageOutgoingBorder;
  final Color surface;
  final Color surfaceElevated;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color textOnPrimary;
}

/// Màu của app. Tên giữ nguyên; giá trị đổi theo bảng đang áp dụng
/// ([apply]). Vì giá trị thay đổi khi chạy nên không dùng trong biểu thức const.
final class WebTuiColors {
  const WebTuiColors._();

  static WebTuiPalette _palette = WebTuiPalette.light;
  static Brightness _brightness = Brightness.light;

  static Brightness get brightness => _brightness;

  static void apply(Brightness brightness) {
    _brightness = brightness;
    _palette = brightness == Brightness.dark
        ? WebTuiPalette.dark
        : WebTuiPalette.light;
  }

  static Color get primary => _palette.primary;
  static Color get primaryPressed => _palette.primaryPressed;
  static Color get primarySoft => _palette.primarySoft;
  static Color get chatHeader => _palette.chatHeader;
  static Color get accentGreen => _palette.accentGreen;
  static Color get accentAmber => _palette.accentAmber;
  static Color get danger => _palette.danger;
  static Color get background => _palette.background;
  static Color get backgroundMuted => _palette.backgroundMuted;
  static Color get chatBackground => _palette.chatBackground;
  static Color get messageIncoming => _palette.messageIncoming;
  static Color get messageOutgoing => _palette.messageOutgoing;
  static Color get messageOutgoingBorder => _palette.messageOutgoingBorder;
  static Color get surface => _palette.surface;
  static Color get surfaceElevated => _palette.surfaceElevated;
  static Color get border => _palette.border;
  static Color get textPrimary => _palette.textPrimary;
  static Color get textSecondary => _palette.textSecondary;
  static Color get textMuted => _palette.textMuted;
  static Color get textOnPrimary => _palette.textOnPrimary;
}

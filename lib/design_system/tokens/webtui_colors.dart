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
    required this.page,
    required this.groupBackground,
    required this.chipBackground,
    required this.hairline,
    required this.primaryFill,
    required this.badge,
  });

  static const light = WebTuiPalette(
    // Xanh thương hiệu đậm hơn một bậc (#0877F2 → #0A6CDE): chữ / biểu tượng xanh
    // trên nền trắng và chữ trắng trên nền xanh đều đạt 4,5:1.
    primary: Color(0xFF0A6CDE),
    primaryPressed: Color(0xFF0858B8),
    primarySoft: Color(0xFFE8F1FD),
    chatHeader: Color(0xFF13A8F7),
    accentGreen: Color(0xFF21A875),
    accentAmber: Color(0xFFE2A12C),
    danger: Color(0xFFE45B5B),
    background: Color(0xFFF6F8FC),
    backgroundMuted: Color(0xFFEEF3F8),
    chatBackground: Color(0xFFE2E9F1),
    messageIncoming: Color(0xFFFFFFFF),
    messageOutgoing: Color(0xFFD9E8FF),
    messageOutgoingBorder: Color(0xFFB9D2F5),
    surface: Color(0xFFFFFFFF),
    surfaceElevated: Color(0xFFFAFCFF),
    border: Color(0xFFDDE6F1),
    textPrimary: Color(0xFF172033),
    textSecondary: Color(0xFF536074),
    // Chữ mờ (giờ, dòng phụ) đạt 4,7:1 trên nền trắng.
    textMuted: Color(0xFF6A7386),
    textOnPrimary: Color(0xFFFFFFFF),
    page: Color(0xFFFFFFFF),
    groupBackground: Color(0xFFF2F4F7),
    chipBackground: Color(0xFFEEF1F5),
    hairline: Color(0xFFE4E8EE),
    primaryFill: Color(0xFF0A6CDE),
    badge: Color(0xFFD92D33),
  );

  static const dark = WebTuiPalette(
    primary: Color(0xFF4C9DFF),
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
    messageOutgoing: Color(0xFF1B4478),
    messageOutgoingBorder: Color(0xFF2A5A96),
    surface: Color(0xFF172131),
    surfaceElevated: Color(0xFF1D2939),
    border: Color(0xFF2A3850),
    textPrimary: Color(0xFFE6ECF5),
    textSecondary: Color(0xFFA7B3C6),
    textMuted: Color(0xFF8D99AD),
    textOnPrimary: Color(0xFFFFFFFF),
    page: Color(0xFF0F1623),
    groupBackground: Color(0xFF080D15),
    chipBackground: Color(0xFF1C2636),
    hairline: Color(0xFF222E40),
    // Nền có chữ trắng ở nền tối (chip đang chọn, số đếm): đạt 4,6:1.
    primaryFill: Color(0xFF2A74D6),
    badge: Color(0xFFD92D33),
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

  /// Nền màn liền mạch (danh sách, cài đặt): trắng ở nền sáng.
  final Color page;

  /// Dải ngăn giữa các nhóm dòng (8px), thay cho thẻ bo góc.
  final Color groupBackground;

  /// Nền chip lọc chưa chọn, ô tìm.
  final Color chipBackground;

  /// Đường kẻ mảnh 0,5px giữa các dòng.
  final Color hairline;

  /// Nền có chữ trắng (chip đang chọn, số chưa đọc, nút chính).
  final Color primaryFill;

  /// Đỏ của số chưa đọc trên biểu tượng tab.
  final Color badge;
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
  static Color get page => _palette.page;
  static Color get groupBackground => _palette.groupBackground;
  static Color get chipBackground => _palette.chipBackground;
  static Color get hairline => _palette.hairline;
  static Color get primaryFill => _palette.primaryFill;
  static Color get badge => _palette.badge;
}

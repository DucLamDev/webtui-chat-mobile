import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_radii.dart';
import '../../../../design_system/tokens/webtui_typography.dart';

/// Một bộ màu "workbench" của IDE: lấy đúng màu IDE web (kiểu VS Code Light /
/// Dark Modern, nhấn tím #8100ff) để app và web nhìn như một. Có hai bộ cố định
/// [light] / [dark]; gắn vào chủ đề bằng [ideWbTheme] nên màn nào cần luôn tối
/// (terminal, trình sửa) đọc bằng [IdeWbPalette.of].
@immutable
class IdeWbPalette extends ThemeExtension<IdeWbPalette> {
  const IdeWbPalette._({
    required this.isDark,
    required this.bg,
    required this.bar,
    required this.chip,
    required this.border,
    required this.borderStrong,
    required this.text,
    required this.textStrong,
    required this.text2,
    required this.accentInk,
    required this.accentSoft,
    required this.codex,
    required this.ok,
    required this.warn,
    required this.danger,
  });

  static const light = IdeWbPalette._(
    isDark: false,
    bg: Colors.white,
    bar: Color(0xFFF8F8F8),
    chip: Color(0xFFF2F2F2),
    border: Color(0xFFE5E5E5),
    borderStrong: Color(0xFFCECECE),
    text: Color(0xFF3B3B3B),
    textStrong: Color(0xFF1F1F1F),
    text2: Color(0xFF616161),
    accentInk: Color(0xFF8100FF),
    accentSoft: Color(0xFFF1E6FF),
    codex: Color(0xFF1F1F1F),
    ok: Color(0xFF1A7F37),
    warn: Color(0xFFB45309),
    danger: Color(0xFFCF222E),
  );

  static const dark = IdeWbPalette._(
    isDark: true,
    bg: Color(0xFF1F1F1F),
    bar: Color(0xFF181818),
    chip: Color(0xFF2A2D2E),
    border: Color(0xFF2B2B2B),
    borderStrong: Color(0xFF3C3C3C),
    text: Color(0xFFCCCCCC),
    textStrong: Colors.white,
    text2: Color(0xFF9D9D9D),
    accentInk: Color(0xFFB37CFF),
    accentSoft: Color(0xFF341A55),
    codex: Colors.white,
    ok: Color(0xFF3FB950),
    warn: Color(0xFFE3A008),
    danger: Color(0xFFF85149),
  );

  /// Bộ màu theo sáng / tối hiện tại của máy.
  static IdeWbPalette get current =>
      WebTuiColors.brightness == Brightness.dark ? dark : light;

  /// Bộ màu của chủ đề đang áp dụng (màn bọc [IdeWbTheme]); ngoài IDE thì
  /// theo máy.
  static IdeWbPalette of(BuildContext context) =>
      Theme.of(context).extension<IdeWbPalette>() ?? current;

  final bool isDark;

  /// Nền vùng làm việc (khung chat, trình sửa).
  final Color bg;

  /// Nền thanh hoạt động, tab, thanh trạng thái, thẻ ô nhập.
  final Color bar;

  /// Nền nút / chip / tin của người dùng.
  final Color chip;
  final Color border;
  final Color borderStrong;

  /// Chữ chính.
  final Color text;

  /// Chữ đậm nhất (tab đang mở, biểu tượng đang chọn).
  final Color textStrong;

  /// Chữ phụ (≥ 4.5:1 trên [bar] và [chip]).
  final Color text2;

  /// Tím dùng cho chữ / biểu tượng / viền: nền tối sáng hơn cho đủ tương phản.
  final Color accentInk;

  /// Nền tím nhạt (chip chế độ, mục đang chọn).
  final Color accentSoft;

  /// Màu biểu tượng Codex.
  final Color codex;
  final Color ok;
  final Color warn;
  final Color danger;

  /// Tím nhấn để tô nền (chữ trắng trên nền này).
  Color get accent => IdeWb.accent;

  Brightness get brightness => isDark ? Brightness.dark : Brightness.light;

  /// Bộ màu này dưới dạng bảng màu chung của app, để widget chung (hộp thoại,
  /// bảng thao tác, chip lọc...) trong IDE cũng tím như IDE web. [primary] là
  /// màu chữ / biểu tượng nhấn, [primaryFill] là nền có chữ trắng.
  WebTuiPalette get webTui => WebTuiPalette(
    primary: accentInk,
    primaryPressed: isDark ? const Color(0xFFC79BFF) : const Color(0xFF6A00D6),
    primarySoft: accentSoft,
    chatHeader: bar,
    accentGreen: ok,
    accentAmber: warn,
    danger: danger,
    background: bg,
    backgroundMuted: chip,
    chatBackground: bg,
    messageIncoming: bar,
    messageOutgoing: chip,
    messageOutgoingBorder: border,
    surface: bg,
    surfaceElevated: bar,
    border: border,
    textPrimary: textStrong,
    textSecondary: text,
    textMuted: text2,
    textOnPrimary: Colors.white,
    page: bg,
    groupBackground: bar,
    chipBackground: chip,
    hairline: border,
    primaryFill: IdeWb.accent,
    badge: danger,
  );

  @override
  IdeWbPalette copyWith() => this;

  @override
  IdeWbPalette lerp(IdeWbPalette? other, double t) =>
      other == null || t < 0.5 ? this : other;
}

/// Màu IDE theo sáng / tối của máy (đọc [WebTuiColors.brightness], đổi cùng lúc
/// với app). Màn luôn tối dùng [IdeWbPalette.of] thay vì lớp này.
abstract final class IdeWb {
  static IdeWbPalette get _p => IdeWbPalette.current;

  static Color get bg => _p.bg;
  static Color get bar => _p.bar;
  static Color get chip => _p.chip;
  static Color get border => _p.border;
  static Color get borderStrong => _p.borderStrong;
  static Color get text => _p.text;
  static Color get textStrong => _p.textStrong;
  static Color get text2 => _p.text2;

  /// Tím nhấn để tô nền (chữ trắng trên nền này).
  static const Color accent = Color(0xFF8100FF);

  static Color get accentInk => _p.accentInk;
  static Color get accentSoft => _p.accentSoft;

  /// Màu biểu tượng Claude (cam đất).
  static const Color claude = Color(0xFFD97757);

  static Color get codex => _p.codex;
  static Color get ok => _p.ok;
  static Color get warn => _p.warn;
  static Color get danger => _p.danger;
}

/// Cỡ chữ của IDE: nhỏ hơn chữ app khoảng 1 điểm để thấy được nhiều nội dung
/// một lúc như IDE web (người dùng chọn 20/11). Cỡ chữ hệ thống (trợ năng) vẫn
/// nhân lên như thường.
abstract final class IdeType {
  static const titleLarge = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w700,
    height: 1.25,
  );

  static const titleMedium = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    height: 1.3,
  );

  static const bodyMedium = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    height: 1.35,
  );

  static const bodySmall = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.35,
  );

  static const labelSmall = WebTuiTypography.labelSmall;

  /// Chữ tin nhắn chat AI và ô gõ.
  static const chat = 14.0;
}

/// Chủ đề Material của IDE: nút, chip, công tắc, thanh tiến độ, đầu trang,
/// bảng trượt dùng màu [IdeWb] và cỡ [IdeType]. Đặt cỡ tuyệt đối nên bọc lồng
/// nhiều lần vẫn như một.
ThemeData ideWbTheme(ThemeData base, {IdeWbPalette? palette}) {
  final p = palette ?? IdeWbPalette.current;
  final t = base.textTheme;
  // Kiểu chữ trong theme thay hẳn kiểu chung (không kế thừa phông), nên phải
  // mang theo phông của app.
  final appFont = t.bodyMedium;
  TextStyle ide(TextStyle s) => s.copyWith(
    fontFamily: appFont?.fontFamily,
    fontFamilyFallback: appFont?.fontFamilyFallback,
  );
  TextStyle? size(TextStyle? s, double v, [FontWeight? w]) =>
      s?.copyWith(fontSize: v, fontWeight: w);
  final textTheme = t
      .copyWith(
        titleLarge: size(t.titleLarge, 18),
        titleMedium: size(t.titleMedium, 15, FontWeight.w600),
        titleSmall: size(t.titleSmall, 13),
        bodyLarge: size(t.bodyLarge, 14),
        bodyMedium: size(t.bodyMedium, 13),
        bodySmall: size(t.bodySmall, 12),
        labelLarge: size(t.labelLarge, 13),
        labelMedium: size(t.labelMedium, 12),
      )
      .apply(bodyColor: p.textStrong, displayColor: p.textStrong);
  final scheme = base.colorScheme.copyWith(
    brightness: p.brightness,
    primary: p.accent,
    onPrimary: Colors.white,
    secondaryContainer: p.accentSoft,
    onSecondaryContainer: p.accentInk,
    surface: p.bg,
    onSurface: p.textStrong,
    onSurfaceVariant: p.text2,
    surfaceContainerLowest: p.bg,
    surfaceContainerLow: p.bar,
    surfaceContainer: p.bar,
    surfaceContainerHigh: p.bar,
    surfaceContainerHighest: p.chip,
    outline: p.borderStrong,
    outlineVariant: p.border,
    error: p.danger,
  );
  // Chữ nút nhỏ hơn nút app một bậc như IDE web. Kiểu IDE đứng trước nên
  // thắng kiểu app khi gộp (merge giữ trường đã có của bên gọi).
  final btnText = WidgetStatePropertyAll(
    ide(
      IdeType.bodyMedium,
    ).copyWith(fontSize: 13.5, fontWeight: FontWeight.w600),
  );
  WidgetStateProperty<Color> fg(Color c) => WidgetStateProperty.resolveWith(
    (s) => s.contains(WidgetState.disabled) ? p.text2 : c,
  );
  // Nút chữ: tím (nền tối dùng tím sáng hơn cho đủ tương phản).
  final ink = ButtonStyle(foregroundColor: fg(p.accentInk), textStyle: btnText);
  // Nút viền: chữ trung tính, viền đậm như nút phụ của IDE web.
  final outline = ButtonStyle(
    foregroundColor: fg(p.textStrong),
    textStyle: btnText,
    side: WidgetStatePropertyAll(BorderSide(color: p.borderStrong)),
  );
  final radius = BorderRadius.circular(WebTuiRadii.md);
  return base.copyWith(
    colorScheme: scheme,
    textTheme: textTheme,
    scaffoldBackgroundColor: p.bg,
    canvasColor: p.bg,
    // Widget chung của app (hộp thoại, bảng thao tác, chip lọc, ô rỗng...)
    // đọc WebTuiColors.of(context): đổi sang màu IDE.
    extensions: [...base.extensions.values, p, WebTuiPaletteScope(p.webTui)],
    dividerColor: p.border,
    dividerTheme: base.dividerTheme.copyWith(color: p.border),
    appBarTheme: base.appBarTheme.copyWith(
      backgroundColor: p.bar,
      foregroundColor: p.textStrong,
      surfaceTintColor: Colors.transparent,
      systemOverlayStyle: p.isDark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      titleTextStyle: ide(IdeType.titleMedium).copyWith(color: p.textStrong),
      shape: Border(bottom: BorderSide(color: p.border)),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ink.merge(base.textButtonTheme.style),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: outline.merge(base.outlinedButtonTheme.style),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        textStyle: btnText,
      ).merge(base.filledButtonTheme.style),
    ),
    // Nút nổi có chữ ("Thêm việc / Ghi chú mới...") gọn như nút chính IDE web:
    // cao 44 (vẫn đủ vùng bấm), chữ 13,5; biểu tượng 18 đặt tại chỗ dùng (để
    // nút tròn chỉ có biểu tượng giữ cỡ cũ).
    floatingActionButtonTheme: base.floatingActionButtonTheme.copyWith(
      backgroundColor: p.accent,
      foregroundColor: Colors.white,
      elevation: 2,
      highlightElevation: 3,
      // Tối thiểu (không cố định) để chữ hệ thống rất to vẫn không bị cắt.
      extendedSizeConstraints: const BoxConstraints(
        minHeight: 44,
        minWidth: 44,
      ),
      extendedPadding: const EdgeInsetsDirectional.only(start: 14, end: 16),
      extendedIconLabelSpacing: 6,
      extendedTextStyle: ide(
        IdeType.bodyMedium,
      ).copyWith(fontSize: 13.5, fontWeight: FontWeight.w600),
    ),
    inputDecorationTheme: base.inputDecorationTheme.copyWith(
      fillColor: p.chip,
      hintStyle: ide(IdeType.bodyMedium).copyWith(color: p.text2),
      labelStyle: ide(IdeType.bodyMedium).copyWith(color: p.text),
      border: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: p.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: p.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: p.accentInk, width: 1.4),
      ),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: p.accentInk,
      selectionColor: p.accent.withValues(alpha: 0.3),
      selectionHandleColor: p.accentInk,
    ),
    progressIndicatorTheme: base.progressIndicatorTheme.copyWith(
      color: p.accentInk,
    ),
    tabBarTheme: base.tabBarTheme.copyWith(
      labelColor: p.accentInk,
      unselectedLabelColor: p.text2,
      indicatorColor: p.accentInk,
      dividerColor: p.border,
    ),
    // Chip chọn (khoảng thời gian, loại máy...) như tab lọc IDE web: không
    // dấu tích, không viền; đang chọn nền tím nhạt chữ tím đậm.
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: p.chip,
      selectedColor: p.accentSoft,
      showCheckmark: false,
      side: BorderSide.none,
      shape: const StadiumBorder(),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      labelStyle: ide(IdeType.bodySmall).copyWith(
        color: WidgetStateColor.resolveWith(
          (s) => s.contains(WidgetState.selected) ? p.accentInk : p.text,
        ),
        fontWeight: FontWeight.w600,
      ),
    ),
    bottomSheetTheme: base.bottomSheetTheme.copyWith(
      backgroundColor: p.bg,
      modalBackgroundColor: p.bg,
      surfaceTintColor: Colors.transparent,
    ),
    dialogTheme: base.dialogTheme.copyWith(
      backgroundColor: p.bg,
      surfaceTintColor: Colors.transparent,
    ),
    popupMenuTheme: base.popupMenuTheme.copyWith(
      color: p.bar,
      surfaceTintColor: Colors.transparent,
      textStyle: ide(IdeType.bodyMedium).copyWith(color: p.textStrong),
    ),
    listTileTheme: base.listTileTheme.copyWith(
      iconColor: p.text,
      textColor: p.textStrong,
    ),
  );
}

/// Bọc một màn IDE bằng [ideWbTheme]. Bảng trượt / hộp thoại mở từ bên trong tự
/// mang chủ đề theo; màn con mở bằng Navigator thì dùng [IdePageRoute].
class IdeWbTheme extends StatelessWidget {
  const IdeWbTheme({required this.child, this.dark = false, super.key});

  final Widget child;

  /// Luôn tối dù máy đang sáng (terminal, trình sửa mã: người dùng chọn 20/11).
  final bool dark;

  @override
  Widget build(BuildContext context) => Theme(
    data: ideWbTheme(
      Theme.of(context),
      palette: dark ? IdeWbPalette.dark : null,
    ),
    child: child,
  );
}

/// Như [MaterialPageRoute] nhưng màn con giữ chủ đề IDE.
class IdePageRoute<T> extends MaterialPageRoute<T> {
  IdePageRoute({
    required super.builder,
    super.settings,
    super.fullscreenDialog,
    this.dark = false,
  });

  /// Màn luôn tối dù máy đang sáng (xem / sửa / so sánh tệp như IDE web).
  final bool dark;

  @override
  Widget buildContent(BuildContext context) =>
      IdeWbTheme(dark: dark, child: super.buildContent(context));
}

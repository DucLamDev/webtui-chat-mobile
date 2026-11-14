import 'package:flutter/widgets.dart';

import '../icons/webtui_icons.dart';

/// Cặp màu của ô biểu tượng kênh: nền nhạt + biểu tượng đậm.
@immutable
final class WebTuiChannelTone {
  const WebTuiChannelTone({required this.background, required this.icon});

  final Color background;
  final Color icon;
}

/// Bảng màu theo loại kênh: mỗi loại một sắc để phân biệt nhanh trong danh sách.
/// Màu biểu tượng so với nền đạt tương phản ≥ 3:1 (có test kiểm).
final class WebTuiChannelColors {
  const WebTuiChannelColors._();

  static const general = WebTuiChannelPair(
    light: WebTuiChannelTone(
      background: Color(0xFFE1EDFF),
      icon: Color(0xFF1D5FD1),
    ),
    dark: WebTuiChannelTone(
      background: Color(0xFF1B2D4D),
      icon: Color(0xFF8DB8FF),
    ),
  );
  static const announcement = WebTuiChannelPair(
    light: WebTuiChannelTone(
      background: Color(0xFFFFEAD5),
      icon: Color(0xFFB84E08),
    ),
    dark: WebTuiChannelTone(
      background: Color(0xFF462A14),
      icon: Color(0xFFFFB574),
    ),
  );
  static const chitchat = WebTuiChannelPair(
    light: WebTuiChannelTone(
      background: Color(0xFFDAF4E8),
      icon: Color(0xFF0B7552),
    ),
    dark: WebTuiChannelTone(
      background: Color(0xFF14382C),
      icon: Color(0xFF6FD9AF),
    ),
  );
  static const bot = WebTuiChannelPair(
    light: WebTuiChannelTone(
      background: Color(0xFFEDE4FF),
      icon: Color(0xFF6A3AD0),
    ),
    dark: WebTuiChannelTone(
      background: Color(0xFF2C2048),
      icon: Color(0xFFBFA2FF),
    ),
  );
  static const private = WebTuiChannelPair(
    light: WebTuiChannelTone(
      background: Color(0xFFE0E4FB),
      icon: Color(0xFF3B3FB5),
    ),
    dark: WebTuiChannelTone(
      background: Color(0xFF23264F),
      icon: Color(0xFFA6ABFF),
    ),
  );
  static const orders = WebTuiChannelPair(
    light: WebTuiChannelTone(
      background: Color(0xFFFCE4F0),
      icon: Color(0xFFB8185A),
    ),
    dark: WebTuiChannelTone(
      background: Color(0xFF47182F),
      icon: Color(0xFFFF9EC6),
    ),
  );
  static const ticket = WebTuiChannelPair(
    light: WebTuiChannelTone(
      background: Color(0xFFFFF1C2),
      icon: Color(0xFF86600A),
    ),
    dark: WebTuiChannelTone(
      background: Color(0xFF40330F),
      icon: Color(0xFFF5CE5E),
    ),
  );
  static const accounting = WebTuiChannelPair(
    light: WebTuiChannelTone(
      background: Color(0xFFD9F2F7),
      icon: Color(0xFF0C6F8A),
    ),
    dark: WebTuiChannelTone(
      background: Color(0xFF123741),
      icon: Color(0xFF69D3EC),
    ),
  );
  static const alert = WebTuiChannelPair(
    light: WebTuiChannelTone(
      background: Color(0xFFFDE6E4),
      icon: Color(0xFFB42318),
    ),
    dark: WebTuiChannelTone(
      background: Color(0xFF481B17),
      icon: Color(0xFFFF9C92),
    ),
  );
  static const fallback = WebTuiChannelPair(
    light: WebTuiChannelTone(
      background: Color(0xFFE6ECF3),
      icon: Color(0xFF475A72),
    ),
    dark: WebTuiChannelTone(
      background: Color(0xFF263040),
      icon: Color(0xFFA9B8CC),
    ),
  );

  static List<WebTuiChannelPair> get all => const [
    general,
    announcement,
    chitchat,
    bot,
    private,
    orders,
    ticket,
    accounting,
    alert,
    fallback,
  ];
}

@immutable
final class WebTuiChannelPair {
  const WebTuiChannelPair({required this.light, required this.dark});

  final WebTuiChannelTone light;
  final WebTuiChannelTone dark;

  WebTuiChannelTone pick(bool darkMode) => darkMode ? dark : light;
}

/// Chọn màu theo biểu tượng loại kênh. Biểu tượng không thuộc danh mục kênh
/// (ví dụ mục hộp thư) trả về `null` để giữ màu mặc định của ô.
WebTuiChannelTone? webTuiChannelTone(IconData icon, {bool dark = false}) {
  final pair = switch (icon) {
    WebTuiIcons.channel => WebTuiChannelColors.general,
    WebTuiIcons.announcement => WebTuiChannelColors.announcement,
    WebTuiIcons.chitchat => WebTuiChannelColors.chitchat,
    WebTuiIcons.bot => WebTuiChannelColors.bot,
    WebTuiIcons.channelPrivate => WebTuiChannelColors.private,
    WebTuiIcons.orders => WebTuiChannelColors.orders,
    WebTuiIcons.ticket => WebTuiChannelColors.ticket,
    WebTuiIcons.accounting => WebTuiChannelColors.accounting,
    WebTuiIcons.bell => WebTuiChannelColors.alert,
    _ => null,
  };
  return pair?.pick(dark);
}

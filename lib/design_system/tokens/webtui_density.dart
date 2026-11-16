final class WebTuiListDensity {
  const WebTuiListDensity._();

  /// Dòng hội thoại kiểu Telegram / Zalo: cao 76, ảnh 56.
  static const double conversationItemHeight = 76;
  static const double compactItemHeight = 60;

  /// Ảnh đại diện mặc định (danh bạ, thành viên): 48.
  static const double avatarSize = 48;

  /// Ảnh đầu dòng trong danh sách hội thoại.
  static const double listAvatarSize = 56;
  static const double compactAvatarSize = 40;
  static const double unreadBadgeMinSize = 20;

  /// Lề trái của dòng; khoảng giữa ảnh và chữ.
  static const double rowPadding = 16;
  static const double avatarGap = 12;

  /// Đường kẻ giữa các dòng thụt vào tới chữ (lề + ảnh + khoảng).
  static const double conversationDividerIndent =
      rowPadding + listAvatarSize + avatarGap;
  static const double contactDividerIndent =
      rowPadding + avatarSize + avatarGap;
}

final class WebTuiBottomTabTokens {
  const WebTuiBottomTabTokens._();

  /// Chiều cao viên thuốc nổi kiểu Telegram (không gồm khoảng trên / dưới).
  static const double height = 64;

  /// Lề hai bên viên thuốc: nội dung chạy hai bên và phía dưới như Telegram.
  static const double sideMargin = 16;

  /// Bề ngang tối đa (máy tính bảng, màn ngang): viên thuốc nằm giữa.
  static const double maxWidth = 520;

  /// Khoảng dưới tối thiểu khi máy không có vùng an toàn đáy: viên thuốc vẫn
  /// nổi cách mép màn hình.
  static const double margin = 12;

  /// Khoảng trong suốt phía trên viên thuốc, tính vào phần thân phải chừa để
  /// mục cuối danh sách không dính sát viên thuốc.
  static const double topGap = 8;

  /// Độ mờ nền phía sau viên thuốc (kính mờ kiểu Telegram / iOS).
  static const double blurSigma = 30;

  /// Khoảng giữa mép viên thuốc và nền của mục đang chọn.
  static const double selectionInset = 4;

  static const double iconSize = 26;
  static const int tabCount = 4;

  /// Chiều cao thanh chiếm ở đáy màn hình khi khoảng dưới viên thuốc là
  /// [bottomGap] (vùng an toàn đáy hoặc [margin]). Danh sách trong tab chính
  /// đệm đáy ít nhất bằng số này để mục cuối không bị viên thuốc che.
  static double reservedHeight(double bottomGap) => topGap + height + bottomGap;
}

final class WebTuiSegmentedControlTokens {
  const WebTuiSegmentedControlTokens._();

  static const double height = 36;
  static const double minSegmentWidth = 72;
}

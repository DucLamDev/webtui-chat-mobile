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

  /// Chiều cao thanh tab dính đáy (không gồm vùng an toàn đáy).
  static const double height = 52;

  /// Thanh dính sát mép màn hình: không lề.
  static const double margin = 0;

  /// Không chừa khoảng trên thanh.
  static const double topGap = 0;

  /// Độ mờ nền phía sau thanh (kiểu kính mờ của Telegram / iOS).
  static const double blurSigma = 20;

  /// Biểu tượng tab không có khung bao nên to hơn (28).
  static const double iconSize = 28;
  static const int tabCount = 4;

  /// Chiều cao thanh chiếm ở đáy màn hình khi khoảng dưới thanh là
  /// [bottomGap] (vùng an toàn đáy hoặc [margin]). Danh sách trong tab chính
  /// đệm đáy ít nhất bằng số này để mục cuối không bị thanh che.
  static double reservedHeight(double bottomGap) => topGap + height + bottomGap;
}

final class WebTuiSegmentedControlTokens {
  const WebTuiSegmentedControlTokens._();

  static const double height = 36;
  static const double minSegmentWidth = 72;
}

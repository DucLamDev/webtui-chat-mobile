final class WebTuiListDensity {
  const WebTuiListDensity._();

  static const double conversationItemHeight = 68;
  static const double compactItemHeight = 54;
  static const double avatarSize = 42;

  /// Ảnh / ô vuông đầu dòng trong danh sách hội thoại.
  static const double listAvatarSize = 48;
  static const double compactAvatarSize = 36;
  static const double unreadBadgeMinSize = 18;
}

final class WebTuiBottomTabTokens {
  const WebTuiBottomTabTokens._();

  /// Chiều cao thanh nổi (không gồm lề và vùng an toàn).
  static const double height = 62;

  /// Lề trái / phải / dưới của thanh nổi so với mép màn hình.
  static const double margin = 14;

  /// Khoảng trên thanh nổi (giữa nội dung và mép trên viên thuốc).
  static const double topGap = 4;

  /// Bo góc viên thuốc và nền mục đang chọn.
  static const double radius = 30;

  /// Độ mờ nền phía sau thanh (kiểu kính mờ của Telegram / iOS).
  static const double blurSigma = 20;
  static const double iconSize = 22;
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

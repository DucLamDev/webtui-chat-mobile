import 'package:flutter/widgets.dart';

import 'phosphor_glyphs.dart';

export 'phosphor_glyphs.dart' show PhosphorDuotoneGlyph;

/// Bộ biểu tượng của app: Phosphor (giấy phép MIT), nét mảnh bo tròn; mỗi
/// biểu tượng có dạng nét (mặc định), dạng đặc (đang chọn) và dạng hai lớp màu
/// cùng một hình.
///
/// Mọi màn gọi biểu tượng theo tên ở đây, không gọi thẳng thư viện, để khi đổi
/// bộ biểu tượng chỉ cần sửa một chỗ. Không bọc biểu tượng trong ô nền: trạng
/// thái chọn thể hiện bằng dạng đặc + màu nhấn.
abstract final class WebTuiIcons {
  // Thanh dưới: dạng nét khi chưa chọn, dạng đặc khi đang chọn.
  static const IconData messages = PhosphorRegular.chatCircleDots;
  static const IconData messagesActive = PhosphorFill.chatCircleDots;
  static const IconData friends = PhosphorRegular.users;
  static const IconData friendsActive = PhosphorFill.users;
  static const IconData work = PhosphorRegular.briefcase;
  static const IconData workActive = PhosphorFill.briefcase;
  static const IconData settings = PhosphorRegular.gearSix;
  static const IconData settingsActive = PhosphorFill.gearSix;

  // Đầu màn và nút chung.
  static const IconData compose = PhosphorRegular.notePencil;
  static const IconData search = PhosphorRegular.magnifyingGlass;
  static const IconData back = PhosphorRegular.caretLeft;
  static const IconData forward = PhosphorRegular.caretRight;
  static const IconData more = PhosphorRegular.dotsThree;

  /// Nút ba gạch (≡): menu gom các việc phụ ở đầu phòng chat.
  static const IconData menu = PhosphorRegular.list;
  static const IconData moreVertical = PhosphorRegular.dotsThreeVertical;
  static const IconData add = PhosphorRegular.plus;
  static const IconData close = PhosphorRegular.x;
  static const IconData edit = PhosphorRegular.pencilSimple;
  static const IconData delete = PhosphorRegular.trash;
  static const IconData dragHandle = PhosphorRegular.dotsSixVertical;
  static const IconData moveUp = PhosphorRegular.arrowUp;
  static const IconData moveDown = PhosphorRegular.arrowDown;
  static const IconData externalLink = PhosphorRegular.arrowSquareOut;
  static const IconData download = PhosphorRegular.downloadSimple;
  static const IconData view = PhosphorRegular.eye;
  static const IconData newMessage = PhosphorRegular.chatCircleText;
  static const IconData newGroup = PhosphorRegular.usersThree;
  static const IconData addFriend = PhosphorRegular.userPlus;

  // Kênh và hội thoại.
  static const IconData channel = PhosphorRegular.hash;
  static const IconData channelPrivate = PhosphorRegular.lockSimple;
  static const IconData announcement = PhosphorRegular.megaphone;
  static const IconData orders = PhosphorRegular.shoppingBag;
  static const IconData ticket = PhosphorRegular.ticket;
  static const IconData chitchat = PhosphorRegular.coffee;
  static const IconData accounting = PhosphorRegular.calculator;
  static const IconData bell = PhosphorRegular.bell;
  static const IconData bellOff = PhosphorRegular.bellSlash;
  static const IconData bellOffFilled = PhosphorFill.bellSlash;
  static const IconData bot = PhosphorRegular.robot;
  static const IconData pin = PhosphorRegular.pushPin;
  static const IconData pinFilled = PhosphorFill.pushPin;

  // Phòng chat.
  static const IconData phone = PhosphorRegular.phone;
  static const IconData phoneCall = PhosphorRegular.phoneCall;
  static const IconData phoneMissed = PhosphorRegular.phoneX;
  static const IconData video = PhosphorRegular.videoCamera;
  static const IconData mic = PhosphorRegular.microphone;
  static const IconData send = PhosphorRegular.paperPlaneRight;
  static const IconData emoji = PhosphorRegular.smiley;
  static const IconData play = PhosphorRegular.play;
  static const IconData pause = PhosphorRegular.pause;
  static const IconData seen = PhosphorRegular.checks;
  static const IconData image = PhosphorRegular.image;
  static const IconData camera = PhosphorRegular.camera;
  static const IconData gallery = PhosphorRegular.images;
  static const IconData documentScan = PhosphorRegular.scan;
  static const IconData qrScan = PhosphorRegular.qrCode;
  static const IconData attach = PhosphorRegular.paperclip;
  static const IconData scheduleSend = PhosphorRegular.clockCountdown;
  static const IconData copy = PhosphorRegular.copy;
  static const IconData like = PhosphorRegular.thumbsUp;
  static const IconData reply = PhosphorRegular.arrowBendUpLeft;
  static const IconData forwardMessage = PhosphorRegular.arrowBendUpRight;
  static const IconData thread = PhosphorRegular.chatsCircle;
  static const IconData reminder = PhosphorRegular.alarm;
  static const IconData reportUser = PhosphorRegular.userMinus;
  static const IconData tapAction = PhosphorRegular.cursorClick;

  // Công việc.
  static const IconData tasks = PhosphorRegular.listChecks;
  static const IconData taskDone = PhosphorRegular.check;
  static const IconData overdue = PhosphorRegular.alarm;
  static const IconData note = PhosphorRegular.notepad;
  static const IconData meetings = PhosphorRegular.calendarDots;
  static const IconData sharedFiles = PhosphorRegular.folderSimple;
  static const IconData file = PhosphorRegular.fileText;
  static const IconData audioFile = PhosphorRegular.fileAudio;
  static const IconData videoFile = PhosphorRegular.fileVideo;

  // Cuộc gọi trong lịch sử chat (hướng gọi).
  static const IconData phoneIncoming = PhosphorRegular.phoneIncoming;
  static const IconData phoneOutgoing = PhosphorRegular.phoneOutgoing;
  static const IconData videoOff = PhosphorRegular.videoCameraSlash;
  static const IconData poll = PhosphorRegular.chartBar;

  // Nhóm và thành viên.
  static const IconData group = PhosphorRegular.usersThree;
  static const IconData addMember = PhosphorRegular.userPlus;
  static const IconData leaveGroup = PhosphorRegular.signOut;
  static const IconData selected = PhosphorRegular.checkCircle;
  static const IconData unselected = PhosphorRegular.circle;
  static const IconData check = PhosphorRegular.check;

  // Tệp, thư mục, ghi chú.
  static const IconData imageFile = PhosphorRegular.fileImage;
  static const IconData spreadsheetFile = PhosphorRegular.fileXls;
  static const IconData share = PhosphorRegular.shareNetwork;
  static const IconData refresh = PhosphorRegular.arrowClockwise;
  static const IconData folderPlus = PhosphorRegular.folderPlus;
  static const IconData folderOpen = PhosphorRegular.folderOpen;
  static const IconData folderEdit = PhosphorRegular.pencilSimpleLine;
  static const IconData tag = PhosphorRegular.tag;
  static const IconData filter = PhosphorRegular.slidersHorizontal;

  // Cài đặt.
  static const IconData workspace = PhosphorRegular.buildings;
  static const IconData compactList = PhosphorRegular.rows;
  static const IconData volume = PhosphorRegular.speakerHigh;
  static const IconData textSize = PhosphorRegular.textAa;
  static const IconData advancedSettings = PhosphorRegular.slidersHorizontal;
  // Trang quản trị (lưới 4 ô như Bảng điều khiển của trang quản trị).
  static const IconData adminPanel = PhosphorRegular.squaresFour;
  static const IconData logout = PhosphorRegular.signOut;

  // Bảo mật / xác thực.
  static const IconData lock = PhosphorRegular.lockKey;
  static const IconData fingerprint = PhosphorRegular.fingerprint;
  static const IconData key = PhosphorRegular.key;
  static const IconData shieldCheck = PhosphorRegular.shieldCheck;
  static const IconData report = PhosphorRegular.flag;
  static const IconData block = PhosphorRegular.prohibit;
  static const IconData unblock = PhosphorRegular.userCheck;

  // Hồ sơ đồng nghiệp, lời chào phòng chat trống.
  static const IconData profile = PhosphorRegular.userCircle;
  static const IconData email = PhosphorRegular.envelopeSimple;
  static const IconData location = PhosphorRegular.mapPin;
  static const IconData startDate = PhosphorRegular.calendarBlank;
  static const IconData wave = PhosphorRegular.handWaving;

  // Thiết lập ứng dụng.
  static const IconData theme = PhosphorRegular.palette;
  static const IconData language = PhosphorRegular.globe;
  static const IconData notificationPermission = PhosphorRegular.bellRinging;
  static const IconData hidePreview = PhosphorRegular.eyeSlash;
  static const IconData quietHours = PhosphorRegular.moon;
  static const IconData micOff = PhosphorRegular.microphoneSlash;
  static const IconData timer = PhosphorRegular.timer;
  static const IconData clearCache = PhosphorRegular.broom;

  /// Dung lượng kho tệp đã tải về máy (Thiết lập).
  static const IconData storage = PhosphorRegular.hardDrives;
  static const IconData feedback = PhosphorRegular.chatCenteredText;
  static const IconData update = PhosphorRegular.arrowCircleUp;
  static const IconData upToDate = PhosphorRegular.sealCheck;
  static const IconData warning = PhosphorRegular.warningCircle;
}

/// Biểu tượng hai lớp màu (nét đậm + nền nhạt cùng màu) cho lưới Ứng dụng ở tab
/// Công việc: thay cho ô vuông màu bao quanh biểu tượng. Vẽ bằng
/// [WebTuiDuotoneIcon] (widget `Icon` thường chỉ vẽ được một lớp).
abstract final class WebTuiDuotoneIcons {
  static const PhosphorDuotoneGlyph meetings = PhosphorDuotone.calendarDots;
  static const PhosphorDuotoneGlyph sharedFiles = PhosphorDuotone.folderSimple;
  static const PhosphorDuotoneGlyph note = PhosphorDuotone.notepad;
  static const PhosphorDuotoneGlyph tasks = PhosphorDuotone.checkSquareOffset;
  static const PhosphorDuotoneGlyph add = PhosphorDuotone.plusCircle;
}

/// Vẽ biểu tượng hai lớp: lớp nền cùng màu, độ đậm 22%, nét đậm phía trên.
class WebTuiDuotoneIcon extends StatelessWidget {
  const WebTuiDuotoneIcon(
    this.glyph, {
    required this.color,
    this.size = 36,
    this.semanticLabel,
    super.key,
  });

  final PhosphorDuotoneGlyph glyph;
  final Color color;
  final double size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          children: [
            Icon(
              glyph.secondary,
              size: size,
              color: color.withValues(alpha: 0.22),
            ),
            Icon(glyph.primary, size: size, color: color),
          ],
        ),
      ),
    );
  }
}

/// Khoá biểu tượng lối tắt ứng dụng do máy chủ trả về (danh sách cố định, cùng
/// bản với máy chủ và trang quản trị). Khoá lạ hiện biểu tượng liên kết.
const webTuiShortcutIconKeys = <String>[
  'link',
  'globe',
  'server',
  'cloud',
  'code',
  'terminal',
  'database',
  'calendar',
  'folder',
  'file-text',
  'chart',
  'shield',
  'shopping-bag',
  'ticket',
  'headphones',
  'mail',
  'book-open',
  'briefcase',
  'wallet',
  'settings',
];

IconData webTuiShortcutIcon(String? key) {
  return switch (key?.trim()) {
    'globe' => PhosphorRegular.globe,
    'server' => PhosphorRegular.hardDrives,
    'cloud' => PhosphorRegular.cloud,
    'code' => PhosphorRegular.code,
    'terminal' => PhosphorRegular.terminalWindow,
    'database' => PhosphorRegular.database,
    'calendar' => PhosphorRegular.calendarBlank,
    'folder' => PhosphorRegular.folderSimple,
    'file-text' => PhosphorRegular.fileText,
    'chart' => PhosphorRegular.chartBar,
    'shield' => PhosphorRegular.shield,
    'shopping-bag' => PhosphorRegular.shoppingBag,
    'ticket' => PhosphorRegular.ticket,
    'headphones' => PhosphorRegular.headphones,
    'mail' => PhosphorRegular.envelopeSimple,
    'book-open' => PhosphorRegular.bookOpen,
    'briefcase' => PhosphorRegular.briefcase,
    'wallet' => PhosphorRegular.wallet,
    'settings' => PhosphorRegular.gearSix,
    _ => PhosphorRegular.link,
  };
}

/// Khoá màu lối tắt do máy chủ trả về. Khoá lạ dùng màu xanh.
const webTuiShortcutColorKeys = <String>[
  'blue',
  'violet',
  'green',
  'orange',
  'red',
  'teal',
  'gray',
];

/// Cặp màu (nền nhạt, màu biểu tượng) cho ô lối tắt.
({Color background, Color foreground}) webTuiShortcutColors(String? key) {
  return switch (key?.trim()) {
    'violet' => (
      background: const Color(0xFFF1ECFE),
      foreground: const Color(0xFF7C4DDB),
    ),
    'green' => (
      background: const Color(0xFFE7F7EE),
      foreground: const Color(0xFF1E9E5A),
    ),
    'orange' => (
      background: const Color(0xFFFFF1E5),
      foreground: const Color(0xFFE07A1F),
    ),
    'red' => (
      background: const Color(0xFFFDECEC),
      foreground: const Color(0xFFD64545),
    ),
    'teal' => (
      background: const Color(0xFFE5F7F6),
      foreground: const Color(0xFF14958C),
    ),
    'gray' => (
      background: const Color(0xFFF0F2F5),
      foreground: const Color(0xFF5B6675),
    ),
    _ => (
      background: const Color(0xFFE8F1FE),
      foreground: const Color(0xFF1677E5),
    ),
  };
}

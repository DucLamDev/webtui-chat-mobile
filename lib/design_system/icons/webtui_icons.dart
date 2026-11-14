import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Bộ biểu tượng của app: nét mảnh bo tròn, cùng họ Lucide với bản web.
///
/// Mọi màn gọi biểu tượng theo tên ở đây, không gọi thẳng thư viện, để khi đổi
/// bộ biểu tượng chỉ cần sửa một chỗ.
abstract final class WebTuiIcons {
  // Thanh dưới.
  static const IconData messages = LucideIcons.messageCircle;
  static const IconData friends = LucideIcons.users;
  // Cặp da có khoá (briefcase-business); `briefcase` thường trông như vali.
  static const IconData work = LucideIcons.briefcaseBusiness;
  static const IconData settings = LucideIcons.settings;

  // Đầu màn và nút chung.
  static const IconData compose = LucideIcons.squarePen;
  static const IconData search = LucideIcons.search;
  static const IconData back = LucideIcons.chevronLeft;
  static const IconData forward = LucideIcons.chevronRight;
  static const IconData more = LucideIcons.ellipsis;
  static const IconData moreVertical = LucideIcons.ellipsisVertical;
  static const IconData add = LucideIcons.plus;
  static const IconData close = LucideIcons.x;
  static const IconData edit = LucideIcons.pencil;
  static const IconData delete = LucideIcons.trash2;
  static const IconData dragHandle = LucideIcons.gripVertical;
  static const IconData moveUp = LucideIcons.arrowUp;
  static const IconData moveDown = LucideIcons.arrowDown;
  static const IconData externalLink = LucideIcons.externalLink;
  static const IconData download = LucideIcons.download;
  static const IconData view = LucideIcons.eye;
  static const IconData newMessage = LucideIcons.messageSquarePlus;
  static const IconData newGroup = LucideIcons.usersRound;
  static const IconData addFriend = LucideIcons.userPlus;

  // Kênh và hội thoại.
  static const IconData channel = LucideIcons.hash;
  static const IconData channelPrivate = LucideIcons.lock;
  static const IconData announcement = LucideIcons.megaphone;
  static const IconData orders = LucideIcons.shoppingBag;
  static const IconData ticket = LucideIcons.ticket;
  static const IconData chitchat = LucideIcons.coffee;
  static const IconData accounting = LucideIcons.calculator;
  static const IconData bell = LucideIcons.bell;
  static const IconData bellOff = LucideIcons.bellOff;
  static const IconData bot = LucideIcons.bot;
  static const IconData pin = LucideIcons.pin;

  // Phòng chat.
  static const IconData phone = LucideIcons.phone;
  static const IconData phoneCall = LucideIcons.phoneCall;
  static const IconData phoneMissed = LucideIcons.phoneMissed;
  static const IconData video = LucideIcons.video;
  static const IconData mic = LucideIcons.mic;
  static const IconData send = LucideIcons.sendHorizontal;
  static const IconData emoji = LucideIcons.smile;
  static const IconData play = LucideIcons.play;
  static const IconData pause = LucideIcons.pause;
  static const IconData seen = LucideIcons.checkCheck;
  static const IconData image = LucideIcons.image;

  // Công việc.
  static const IconData tasks = LucideIcons.listChecks;
  static const IconData taskDone = LucideIcons.check;
  static const IconData note = LucideIcons.notebookPen;
  static const IconData meetings = LucideIcons.calendarDays;
  static const IconData sharedFiles = LucideIcons.folder;
  static const IconData file = LucideIcons.fileText;
  static const IconData audioFile = LucideIcons.fileAudio;
  static const IconData videoFile = LucideIcons.fileVideo;

  // Cuộc gọi trong lịch sử chat (hướng gọi).
  static const IconData phoneIncoming = LucideIcons.phoneIncoming;
  static const IconData phoneOutgoing = LucideIcons.phoneOutgoing;
  static const IconData videoOff = LucideIcons.videoOff;
  static const IconData poll = LucideIcons.chartColumn;

  // Nhóm và thành viên.
  static const IconData group = LucideIcons.usersRound;
  static const IconData addMember = LucideIcons.userRoundPlus;
  static const IconData selected = LucideIcons.circleCheck;
  static const IconData unselected = LucideIcons.circle;
  static const IconData check = LucideIcons.check;

  // Tệp, thư mục, ghi chú.
  static const IconData imageFile = LucideIcons.fileImage;
  static const IconData spreadsheetFile = LucideIcons.fileSpreadsheet;
  static const IconData share = LucideIcons.share2;
  static const IconData refresh = LucideIcons.refreshCw;
  static const IconData folderPlus = LucideIcons.folderPlus;
  static const IconData folderOpen = LucideIcons.folderOpen;
  static const IconData folderEdit = LucideIcons.folderPen;
  static const IconData tag = LucideIcons.tag;
  static const IconData filter = LucideIcons.slidersHorizontal;

  // Bảo mật / xác thực.
  static const IconData lock = LucideIcons.lockKeyhole;
  static const IconData fingerprint = LucideIcons.fingerprint;
  static const IconData key = LucideIcons.keyRound;
  static const IconData shieldCheck = LucideIcons.shieldCheck;
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
    'globe' => LucideIcons.globe,
    'server' => LucideIcons.server,
    'cloud' => LucideIcons.cloud,
    'code' => LucideIcons.code,
    'terminal' => LucideIcons.terminal,
    'database' => LucideIcons.database,
    'calendar' => LucideIcons.calendar,
    'folder' => LucideIcons.folder,
    'file-text' => LucideIcons.fileText,
    'chart' => LucideIcons.chartColumn,
    'shield' => LucideIcons.shield,
    'shopping-bag' => LucideIcons.shoppingBag,
    'ticket' => LucideIcons.ticket,
    'headphones' => LucideIcons.headphones,
    'mail' => LucideIcons.mail,
    'book-open' => LucideIcons.bookOpen,
    'briefcase' => LucideIcons.briefcase,
    'wallet' => LucideIcons.wallet,
    'settings' => LucideIcons.settings,
    _ => LucideIcons.link,
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

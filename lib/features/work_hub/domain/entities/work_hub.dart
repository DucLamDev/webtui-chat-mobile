/// Lối tắt ứng dụng do quản trị thêm cho workspace (mở liên kết ngoài).
final class AppShortcut {
  const AppShortcut({
    required this.id,
    required this.title,
    required this.url,
    this.icon = 'link',
    this.color = 'blue',
    this.position = 0,
  });

  final String id;
  final String title;
  final String url;
  final String icon;
  final String color;
  final int position;
}

/// Danh sách lối tắt kèm quyền quản lý của người gọi.
final class AppShortcutList {
  const AppShortcutList({required this.shortcuts, required this.canManage});

  final List<AppShortcut> shortcuts;
  final bool canManage;
}

/// Nội dung gửi lên khi thêm / sửa lối tắt.
final class AppShortcutDraft {
  const AppShortcutDraft({
    required this.title,
    required this.url,
    this.icon = 'link',
    this.color = 'blue',
  });

  final String title;
  final String url;
  final String icon;
  final String color;
}

/// Số việc của tôi theo trạng thái (`doneLast7Days`: xong trong 7 ngày qua).
final class AssignedTaskSummary {
  const AssignedTaskSummary({
    this.open = 0,
    this.inProgress = 0,
    this.doneLast7Days = 0,
  });

  final int open;
  final int inProgress;
  final int doneLast7Days;
}

/// Một cuộc họp sắp tới trong các kênh người dùng tham gia.
final class UpcomingMeeting {
  const UpcomingMeeting({
    required this.id,
    required this.channelId,
    required this.channelName,
    required this.title,
    required this.startsAt,
    required this.endsAt,
    this.status = 'scheduled',
  });

  final String id;
  final String channelId;
  final String channelName;
  final String title;
  final DateTime startsAt;
  final DateTime? endsAt;
  final String status;

  bool get isActive => status == 'active';
}

/// Loại tệp để lọc trong màn Tệp chia sẻ.
enum SharedFileKind {
  image,
  video,
  audio,
  document;

  static SharedFileKind fromMime(String mimeType) {
    final mime = mimeType.trim().toLowerCase();
    if (mime.startsWith('image/')) return image;
    if (mime.startsWith('video/')) return video;
    if (mime.startsWith('audio/')) return audio;
    return document;
  }
}

/// Tệp đã chia sẻ trong workspace.
final class SharedFile {
  const SharedFile({
    required this.id,
    required this.name,
    required this.mimeType,
    required this.byteSize,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String mimeType;
  final int byteSize;
  final DateTime createdAt;

  SharedFileKind get kind => SharedFileKind.fromMime(mimeType);
}

/// Đường dẫn phát dần của một tệp (video / ghi âm), có hạn dùng.
final class SharedFileStreamLink {
  const SharedFileStreamLink({required this.url, required this.expiresAt});

  /// Đường dẫn máy chủ trả về (thường tương đối, tự mang mã truy cập).
  final String url;

  /// Hết hạn; null khi máy chủ không báo.
  final DateTime? expiresAt;
}

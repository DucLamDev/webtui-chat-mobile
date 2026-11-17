import 'dart:convert';

import 'conversation_summary.dart';

/// Tuỳ chọn danh sách hội thoại lưu trên máy (máy chủ chưa có API): ghim, đánh
/// dấu chưa đọc, ẩn / gỡ khỏi danh sách. Khoá theo `channelId`.
///
/// - Ghim: [pinned] ghim trên máy; [unpinned] bỏ ghim một hội thoại máy chủ
///   đang báo là ghim (`is_favorite`).
/// - Chưa đọc: hội thoại không còn tin chưa đọc vẫn hiện chấm / số 1 cho tới
///   khi mở lại.
/// - Ẩn: ẩn tới khi có tin mới hơn lúc ẩn (`updatedAt` sau mốc ẩn) thì tự hiện
///   lại; vẫn tìm thấy bằng ô tìm.
final class ConversationListPrefs {
  const ConversationListPrefs({
    this.pinned = const {},
    this.unpinned = const {},
    this.markedUnread = const {},
    this.hiddenAt = const {},
  });

  final Set<String> pinned;
  final Set<String> unpinned;
  final Set<String> markedUnread;
  final Map<String, DateTime> hiddenAt;

  static const empty = ConversationListPrefs();

  bool get isEmpty =>
      pinned.isEmpty &&
      unpinned.isEmpty &&
      markedUnread.isEmpty &&
      hiddenAt.isEmpty;

  bool isPinned(ConversationSummary item) {
    final id = item.channelId;
    if (pinned.contains(id)) return true;
    if (unpinned.contains(id)) return false;
    return item.favorite;
  }

  bool isMarkedUnread(ConversationSummary item) =>
      markedUnread.contains(item.channelId);

  /// Mốc hoạt động dùng để so với mốc ẩn: tin cuối, không có thì `updatedAt`.
  static DateTime activityOf(ConversationSummary item) =>
      item.lastMessageAt ?? item.updatedAt;

  /// Đang ẩn: có mốc ẩn và chưa có hoạt động nào mới hơn mốc đó.
  bool isHidden(ConversationSummary item) {
    final at = hiddenAt[item.channelId];
    return at != null && !activityOf(item).isAfter(at);
  }

  /// Bản hội thoại sau khi áp ghim / chưa đọc của máy.
  ConversationSummary apply(ConversationSummary item) {
    if (isEmpty) return item;
    final favorite = isPinned(item);
    final unread = isMarkedUnread(item) && item.unreadCount == 0
        ? 1
        : item.unreadCount;
    if (favorite == item.favorite && unread == item.unreadCount) return item;
    return item.copyWith(favorite: favorite, unreadCount: unread);
  }

  /// Ghim / bỏ ghim trên máy; ghi đè giá trị ghim của máy chủ.
  ConversationListPrefs withPinned(String channelId, bool value) {
    final nextPinned = {...pinned};
    final nextUnpinned = {...unpinned};
    if (value) {
      nextPinned.add(channelId);
      nextUnpinned.remove(channelId);
    } else {
      nextPinned.remove(channelId);
      nextUnpinned.add(channelId);
    }
    return _copy(pinned: nextPinned, unpinned: nextUnpinned);
  }

  ConversationListPrefs withMarkedUnread(String channelId, bool value) {
    final next = {...markedUnread};
    value ? next.add(channelId) : next.remove(channelId);
    return _copy(markedUnread: next);
  }

  /// Ẩn tại mốc [at] (thường là `updatedAt` của hội thoại lúc ẩn) hoặc bỏ ẩn
  /// khi [at] là `null`. Ẩn thì bỏ luôn đánh dấu chưa đọc.
  ConversationListPrefs withHidden(String channelId, DateTime? at) {
    final next = {...hiddenAt};
    if (at == null) {
      next.remove(channelId);
      return _copy(hiddenAt: next);
    }
    next[channelId] = at;
    return _copy(
      hiddenAt: next,
      markedUnread: {...markedUnread}..remove(channelId),
    );
  }

  /// Gỡ hẳn mọi tuỳ chọn của một hội thoại (khi gỡ khỏi danh sách: không còn
  /// ghim / chưa đọc, chỉ giữ mốc ẩn).
  ConversationListPrefs removed(String channelId, DateTime at) {
    return ConversationListPrefs(
      pinned: {...pinned}..remove(channelId),
      unpinned: {...unpinned}..add(channelId),
      markedUnread: {...markedUnread}..remove(channelId),
      hiddenAt: {...hiddenAt, channelId: at},
    );
  }

  ConversationListPrefs _copy({
    Set<String>? pinned,
    Set<String>? unpinned,
    Set<String>? markedUnread,
    Map<String, DateTime>? hiddenAt,
  }) {
    return ConversationListPrefs(
      pinned: pinned ?? this.pinned,
      unpinned: unpinned ?? this.unpinned,
      markedUnread: markedUnread ?? this.markedUnread,
      hiddenAt: hiddenAt ?? this.hiddenAt,
    );
  }

  String encode() => jsonEncode({
    'v': 1,
    'pinned': pinned.toList(),
    'unpinned': unpinned.toList(),
    'unread': markedUnread.toList(),
    'hidden': {
      for (final entry in hiddenAt.entries)
        entry.key: entry.value.toUtc().toIso8601String(),
    },
  });

  /// Đọc chuỗi đã lưu; hỏng / lạ thì trả rỗng (không làm hỏng danh sách).
  static ConversationListPrefs decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return empty;
    try {
      final map = jsonDecode(raw);
      if (map is! Map) return empty;
      Set<String> ids(Object? value) => {
        if (value is List)
          for (final item in value)
            if (item is String && item.trim().isNotEmpty) item.trim(),
      };
      final hidden = <String, DateTime>{};
      final rawHidden = map['hidden'];
      if (rawHidden is Map) {
        for (final entry in rawHidden.entries) {
          final key = entry.key;
          final at = entry.value is String
              ? DateTime.tryParse(entry.value as String)
              : null;
          if (key is String && key.trim().isNotEmpty && at != null) {
            hidden[key.trim()] = at;
          }
        }
      }
      return ConversationListPrefs(
        pinned: ids(map['pinned']),
        unpinned: ids(map['unpinned']),
        markedUnread: ids(map['unread']),
        hiddenAt: hidden,
      );
    } on FormatException {
      return empty;
    }
  }
}

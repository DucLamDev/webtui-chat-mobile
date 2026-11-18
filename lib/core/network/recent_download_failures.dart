import 'dart:collection';

import 'redirect_safe_file_downloader.dart';

/// Nhớ tạm các địa chỉ tải vừa bị máy chủ từ chối hẳn (403 / 404 / 410), để
/// mỗi lần vẽ lại ảnh không hỏi lại máy chủ (17/11/2026: một ảnh đại diện bị
/// 403 bị app hỏi lại 42 lần). Hết [ttl] thì cho thử lại vì quyền hoặc tệp có
/// thể đã đổi. Lỗi mạng, 401 (token hết hạn), 5xx không được nhớ.
final class RecentDownloadFailures {
  RecentDownloadFailures({
    this.ttl = const Duration(minutes: 10),
    this.maxEntries = 512,
    DateTime Function()? now,
  }) : assert(maxEntries > 0),
       _now = now ?? DateTime.now;

  final Duration ttl;
  final int maxEntries;
  final DateTime Function() _now;
  final LinkedHashMap<String, DateTime> _blockedUntil = LinkedHashMap();

  /// Địa chỉ [key] vừa bị từ chối và chưa hết [ttl].
  bool isBlocked(String key) {
    final until = _blockedUntil[key];
    if (until == null) return false;
    if (_now().isBefore(until)) return true;
    _blockedUntil.remove(key);
    return false;
  }

  /// Ghi nhận lỗi tải [error] của [key]; trả `true` khi đó là lỗi từ chối hẳn
  /// (đã nhớ lại).
  bool record(String key, Object error) {
    if (!isPermanentDownloadFailure(error)) return false;
    _blockedUntil.remove(key);
    _blockedUntil[key] = _now().add(ttl);
    while (_blockedUntil.length > maxEntries) {
      _blockedUntil.remove(_blockedUntil.keys.first);
    }
    return true;
  }

  void clear() => _blockedUntil.clear();
}

/// Máy chủ đã trả lời rõ là không có / không cho tải (403, 404, 410).
bool isPermanentDownloadFailure(Object error) {
  return error is RedirectSafeDownloadException &&
      const {403, 404, 410}.contains(error.statusCode);
}

/// Bộ nhớ lỗi tải dùng chung cho ảnh trong tin nhắn và ảnh đại diện.
final RecentDownloadFailures mediaDownloadFailures = RecentDownloadFailures();

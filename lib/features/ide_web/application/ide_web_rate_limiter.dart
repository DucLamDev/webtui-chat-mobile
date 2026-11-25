/// Giới hạn tần suất theo cửa sổ trượt. Sống suốt đời app để đóng mở màn không
/// xoá được hạn mức.
final class IdeWebRateLimiter {
  IdeWebRateLimiter({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  final _hits = <String, List<DateTime>>{};

  /// Ghi một lượt; `false` khi đã đủ [limit] lượt trong [window].
  bool allow(String key, {required int limit, required Duration window}) {
    final now = _clock();
    final hits = _hits.putIfAbsent(key, () => [])
      ..removeWhere((at) => now.difference(at) >= window || at.isAfter(now));
    if (hits.length >= limit) return false;
    hits.add(now);
    return true;
  }
}

/// Hộp hỏi do trang tự gây ra mà không qua cầu nối (micro, liên kết ngoài).
bool ideWebAllowPrompt(IdeWebRateLimiter limiter) =>
    limiter.allow('prompt', limit: 5, window: const Duration(minutes: 1));

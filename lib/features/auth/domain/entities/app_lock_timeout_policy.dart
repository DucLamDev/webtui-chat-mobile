/// Thời gian tự khoá ứng dụng (lõi 3.1).
///
/// Máy chủ đặt mức tối đa `privacy_policy.idle_lock_minutes` (0 = không ép).
/// Người dùng chỉ được chọn ngắn hơn hoặc bằng mức đó. Ứng dụng tự khoá khi
/// không chạm vào app quá N phút, hoặc chạy nền quá N phút; không khoá khi đang
/// gọi.
abstract final class AppLockTimeoutPolicy {
  /// Mặc định khi máy chủ không ép và người dùng chưa chọn.
  static const fallbackMinutes = 30;

  /// Các mức người dùng chọn được (phút).
  static const presetMinutes = <int>[1, 5, 15, 30, 60, 120, 240];

  /// Số phút có hiệu lực. `userMinutes` null hoặc không hợp lệ thì dùng mặc định
  /// (= mức máy chủ, hoặc 30 phút khi máy chủ không ép).
  static int effectiveMinutes({
    required int serverMaxMinutes,
    int? userMinutes,
  }) {
    final serverMax = serverMaxMinutes > 0 ? serverMaxMinutes : 0;
    final fallback = serverMax > 0 ? serverMax : fallbackMinutes;
    final chosen = userMinutes != null && userMinutes > 0
        ? userMinutes
        : fallback;
    if (serverMax > 0 && chosen > serverMax) {
      return serverMax;
    }
    return chosen;
  }

  /// Các lựa chọn hiển thị trong cài đặt: chỉ mức ≤ mức máy chủ (luôn có đúng
  /// mức máy chủ để người dùng chọn lại được mặc định).
  static List<int> allowedChoices(int serverMaxMinutes) {
    if (serverMaxMinutes <= 0) {
      return presetMinutes;
    }
    final choices = presetMinutes
        .where((minutes) => minutes <= serverMaxMinutes)
        .toList();
    if (!choices.contains(serverMaxMinutes)) {
      choices.add(serverMaxMinutes);
    }
    return choices;
  }

  /// Đã quá thời gian kể từ `since` chưa.
  static bool hasExpired({
    required DateTime since,
    required DateTime now,
    required int minutes,
  }) {
    if (minutes <= 0) {
      return false;
    }
    return !now.difference(since).isNegative &&
        now.difference(since) >= Duration(minutes: minutes);
  }

  /// Nhãn tiếng Việt cho một mức.
  static String label(int minutes) {
    if (minutes >= 60 && minutes % 60 == 0) {
      return '${minutes ~/ 60} giờ';
    }
    return '$minutes phút';
  }
}

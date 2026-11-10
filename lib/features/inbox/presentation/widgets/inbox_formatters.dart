/// Giờ ngắn cho danh sách: hôm nay `HH:mm`, khác ngày `dd/MM`, khác năm
/// `dd/MM/yyyy`.
String formatInboxTime(DateTime? time, {DateTime? now}) {
  if (time == null) return '';
  final current = now ?? DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  if (time.year == current.year &&
      time.month == current.month &&
      time.day == current.day) {
    return '${two(time.hour)}:${two(time.minute)}';
  }
  final day = '${two(time.day)}/${two(time.month)}';
  return time.year == current.year ? day : '$day/${time.year}';
}

/// Giờ đầy đủ trong hội thoại.
String formatInboxMessageTime(DateTime time, {DateTime? now}) {
  String two(int v) => v.toString().padLeft(2, '0');
  final clock = '${two(time.hour)}:${two(time.minute)}';
  final current = now ?? DateTime.now();
  if (time.year == current.year &&
      time.month == current.month &&
      time.day == current.day) {
    return clock;
  }
  return '$clock ${formatInboxTime(time, now: current)}';
}

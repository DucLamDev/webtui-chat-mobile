/// Mức gấp của hạn việc để tô màu.
enum TaskDueUrgency { none, soon, overdue }

const _weekdayLabels = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];

String _two(int value) => value.toString().padLeft(2, '0');

/// Hạn theo giờ máy: "Hôm nay 17:00", "Ngày mai 09:00", "Hôm qua 17:00",
/// "T4, 05/11 17:00" (cùng năm) hoặc "05/11/2027 17:00".
String formatTaskDue(DateTime due, DateTime now) {
  final local = due.toLocal();
  final current = now.toLocal();
  // So ngày theo lịch (UTC để không lệch giờ mùa hè).
  final today = DateTime.utc(current.year, current.month, current.day);
  final day = DateTime.utc(local.year, local.month, local.day);
  final days = day.difference(today).inDays;
  final time = '${_two(local.hour)}:${_two(local.minute)}';
  switch (days) {
    case 0:
      return 'Hôm nay $time';
    case 1:
      return 'Ngày mai $time';
    case -1:
      return 'Hôm qua $time';
  }
  final date = '${_two(local.day)}/${_two(local.month)}';
  if (local.year == current.year) {
    return '${_weekdayLabels[local.weekday - 1]}, $date $time';
  }
  return '$date/${local.year} $time';
}

/// Quá hạn khi đã qua; sắp đến hạn khi còn dưới 24 giờ.
TaskDueUrgency taskDueUrgency(
  DateTime? due,
  DateTime now, {
  bool active = true,
}) {
  if (due == null || !active) return TaskDueUrgency.none;
  if (due.isBefore(now)) return TaskDueUrgency.overdue;
  if (due.difference(now) < const Duration(hours: 24)) {
    return TaskDueUrgency.soon;
  }
  return TaskDueUrgency.none;
}

/// Lựa chọn nhanh cho hạn: hôm nay 17:00 (nếu chưa qua), ngày mai 09:00,
/// thứ Hai tuần sau 09:00.
List<({String label, DateTime value})> quickTaskDueOptions(DateTime now) {
  final local = now.toLocal();
  final today = DateTime(local.year, local.month, local.day);
  final todayFive = today.add(const Duration(hours: 17));
  final tomorrowNine = DateTime(local.year, local.month, local.day + 1, 9);
  final daysToMonday = 8 - local.weekday; // thứ Hai tuần sau
  final nextMonday = DateTime(
    local.year,
    local.month,
    local.day + daysToMonday,
    9,
  );
  return [
    if (todayFive.isAfter(local)) (label: 'Hôm nay 17:00', value: todayFive),
    (label: 'Ngày mai 09:00', value: tomorrowNine),
    (label: 'Thứ Hai tuần sau', value: nextMonday),
  ];
}

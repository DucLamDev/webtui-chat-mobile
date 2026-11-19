/// Ngày hạn và giờ hiện cho nhóm màn Việc / Nhật ký (GĐ3).
///
/// Hạn việc là NGÀY ĐỊA PHƯƠNG dạng `YYYY-MM-DD`: không đổi qua UTC / ISO nên
/// không lệch một ngày ở đầu / cuối tháng hay khi múi giờ khác 0.
library;

String _two(int v) => v.toString().padLeft(2, '0');

/// Ngày chọn từ bộ chọn ngày (giờ địa phương) → `YYYY-MM-DD`, theo đúng ngày
/// người dùng nhìn thấy.
String ideFormatDue(DateTime picked) {
  final y = picked.year.toString().padLeft(4, '0');
  return '$y-${_two(picked.month)}-${_two(picked.day)}';
}

/// `YYYY-MM-DD` → ngày 00:00 địa phương; sai định dạng / ngày không có thật
/// (30/02) → `null`.
DateTime? ideParseDue(Object? raw) {
  if (raw is! String) return null;
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(raw);
  if (m == null) return null;
  final y = int.parse(m[1]!);
  final mo = int.parse(m[2]!);
  final d = int.parse(m[3]!);
  final date = DateTime(y, mo, d);
  if (date.year != y || date.month != mo || date.day != d) return null;
  return date;
}

enum IdeDueState { none, overdue, today, soon, later }

/// Số ngày lịch từ hôm nay tới hạn (âm = quá hạn); `null` khi không có hạn.
int? ideDueDays(String? due, DateTime now) {
  final date = ideParseDue(due);
  if (date == null) return null;
  // So bằng ngày lịch (UTC) để giờ mùa hè không làm lệch một ngày.
  final a = DateTime.utc(date.year, date.month, date.day);
  final b = DateTime.utc(now.year, now.month, now.day);
  return a.difference(b).inDays;
}

IdeDueState ideDueState(String? due, DateTime now, {bool done = false}) {
  final days = ideDueDays(due, now);
  if (days == null || done) return IdeDueState.none;
  if (days < 0) return IdeDueState.overdue;
  if (days == 0) return IdeDueState.today;
  return days <= 2 ? IdeDueState.soon : IdeDueState.later;
}

/// `YYYY-MM-DD` → `dd/mm/yyyy` (sai định dạng giữ nguyên).
String ideDueDisplay(String due) {
  final d = ideParseDue(due);
  if (d == null) return due;
  return '${_two(d.day)}/${_two(d.month)}/${d.year}';
}

/// Giây Unix (số nguyên hoặc thực) → giờ địa phương; không hợp lệ → `null`.
DateTime? ideTimeFromSeconds(Object? seconds) {
  if (seconds is! num || !seconds.isFinite || seconds <= 0) return null;
  final ms = seconds * 1000;
  // Ngoài khoảng DateTime chấp nhận (±8.64e15 ms): coi là không có.
  if (ms.abs() > 8.64e15) return null;
  return DateTime.fromMillisecondsSinceEpoch(ms.round());
}

/// `dd/mm HH:mm`, khác năm hiện tại thì thêm năm.
String ideFormatDateTime(DateTime t, {DateTime? now}) {
  final cur = now ?? DateTime.now();
  final date = t.year == cur.year
      ? '${_two(t.day)}/${_two(t.month)}'
      : '${_two(t.day)}/${_two(t.month)}/${t.year}';
  return '$date ${_two(t.hour)}:${_two(t.minute)}';
}

/// Số nguyên an toàn từ JSON: vô cực / NaN / không phải số → [fallback].
int ideSafeInt(Object? v, [int fallback = 0]) {
  if (v is int) return v;
  if (v is num && v.isFinite && v.abs() < 9e15) return v.toInt();
  return fallback;
}

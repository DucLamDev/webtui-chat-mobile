import 'package:webtui_chat/l10n/app_strings.dart';

import '../../domain/entities/customer_ticket.dart';

/// Giờ Việt Nam (UTC+7, không đổi giờ theo mùa), không phụ thuộc múi giờ máy:
/// trả về DateTime UTC mà các trường giờ / ngày là giờ Việt Nam.
DateTime vietnamWallClock(DateTime value) {
  return value.toUtc().add(const Duration(hours: 7));
}

String _two(int value) => value.toString().padLeft(2, '0');

bool _sameDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

/// Nhãn giờ ở danh sách: hôm nay "HH:mm", hôm qua "Hôm qua", còn lại ngày.
String customerTicketListTime(DateTime? value, DateTime now) {
  if (value == null) return '';
  final local = vietnamWallClock(value);
  final today = vietnamWallClock(now);
  if (_sameDay(local, today)) {
    return '${_two(local.hour)}:${_two(local.minute)}';
  }
  final yesterday = today.subtract(const Duration(days: 1));
  if (_sameDay(local, yesterday)) return tr('Hôm qua', 'Yesterday');
  if (local.year == today.year) {
    return '${_two(local.day)}/${_two(local.month)}';
  }
  return '${_two(local.day)}/${_two(local.month)}/${local.year}';
}

/// Giờ của một tin: "HH:mm", kèm ngày nếu không phải hôm nay.
String customerTicketMessageTime(DateTime? value, DateTime now) {
  if (value == null) return '';
  final local = vietnamWallClock(value);
  final today = vietnamWallClock(now);
  final time = '${_two(local.hour)}:${_two(local.minute)}';
  if (_sameDay(local, today)) return time;
  if (local.year == today.year) {
    return '$time ${_two(local.day)}/${_two(local.month)}';
  }
  return '$time ${_two(local.day)}/${_two(local.month)}/${local.year}';
}

String customerTicketDate(DateTime? value) {
  if (value == null) return '';
  final local = vietnamWallClock(value);
  return '${_two(local.day)}/${_two(local.month)}/${local.year}';
}

/// Số phút khách chờ (chỉ ticket chưa trả lời).
int? customerTicketWaitingMinutes(CustomerTicketSummary ticket, DateTime now) {
  final since = ticket.waitingFrom;
  if (since == null) return null;
  final minutes = now.toUtc().difference(since.toUtc()).inMinutes;
  return minutes < 0 ? 0 : minutes;
}

enum CustomerTicketWaitingTone { normal, warning, late }

/// Vàng khi chờ quá 30 phút, đỏ khi quá 2 giờ.
CustomerTicketWaitingTone customerTicketWaitingTone(int? minutes) {
  if (minutes == null || minutes <= 30) return CustomerTicketWaitingTone.normal;
  return minutes > 120
      ? CustomerTicketWaitingTone.late
      : CustomerTicketWaitingTone.warning;
}

String customerTicketWaitingLabel(int minutes) {
  if (minutes < 1) return tr('Vừa gửi', 'Just sent');
  if (minutes < 60) return tr('Chờ $minutes phút', 'Waiting $minutes min');
  if (minutes < 24 * 60) {
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    return rest == 0
        ? tr('Chờ $hours giờ', 'Waiting $hours h')
        : tr('Chờ $hours giờ $rest phút', 'Waiting $hours h $rest min');
  }
  return tr(
    'Chờ ${minutes ~/ (24 * 60)} ngày',
    'Waiting ${minutes ~/ (24 * 60)} days',
  );
}

String customerTicketStatusLabel(CustomerTicketStatus status) {
  return switch (status) {
    CustomerTicketStatus.unanswered => tr('Chưa trả lời', 'Unanswered'),
    CustomerTicketStatus.answered => tr('Đã trả lời', 'Answered'),
    CustomerTicketStatus.closed => tr('Đã đóng', 'Closed'),
    CustomerTicketStatus.unknown => '',
  };
}

Map<String, String> get _categoryLabels => {
  'gia_han': tr('Gia hạn', 'Renewal'),
  'huong_dan': tr('Hướng dẫn', 'How-to'),
  'khac': tr('Khác', 'Other'),
  'khieu_nai': tr('Khiếu nại', 'Complaint'),
  'ky_thuat': tr('Kỹ thuật', 'Technical'),
  'mua_hang': tr('Mua hàng', 'Purchase'),
  'thanh_toan': tr('Thanh toán', 'Payment'),
};

String customerTicketCategoryLabel(String category) {
  final key = category.trim().toLowerCase();
  return _categoryLabels[key] ?? category.trim();
}

Map<String, String> get _serviceStatusLabels => {
  'active': tr('Đang chạy', 'Running'),
  'running': tr('Đang chạy', 'Running'),
  'pending': tr('Chờ xử lý', 'Pending'),
  'suspended': tr('Tạm ngưng', 'Suspended'),
  'expired': tr('Hết hạn', 'Expired'),
  'cancelled': tr('Đã huỷ', 'Canceled'),
  'canceled': tr('Đã huỷ', 'Canceled'),
  'terminated': tr('Đã huỷ', 'Canceled'),
};

/// Trạng thái dịch vụ của khách; giá trị lạ giữ nguyên như máy chủ trả.
String customerTicketServiceStatusLabel(String status) {
  final key = status.trim().toLowerCase();
  return _serviceStatusLabels[key] ?? status.trim();
}

/// "1.234.567 đ".
String formatCustomerTicketMoney(double value) {
  final rounded = value.round();
  final digits = rounded.abs().toString();
  final buffer = StringBuffer(rounded < 0 ? '-' : '');
  for (var index = 0; index < digits.length; index++) {
    if (index > 0 && (digits.length - index) % 3 == 0) buffer.write('.');
    buffer.write(digits[index]);
  }
  return '$buffer đ';
}

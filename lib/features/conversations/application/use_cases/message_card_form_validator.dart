import '../../domain/entities/message_card.dart';

/// Kiểm biểu mẫu của thẻ ở client cho người dùng sửa ngay. Máy chủ vẫn kiểm lại
/// theo thẻ đã lưu, không tin dữ liệu gửi lên.
///
/// [values] là giá trị đang nhập theo `field.id`: chữ (`text`, `textarea`,
/// `number`), giá trị lựa chọn (`select`), `YYYY-MM-DD` hoặc [DateTime]
/// (`date`), `bool` (`checkbox`). Trả lỗi theo `field.id` (rỗng = hợp lệ).
Map<String, String> validateMessageCardForm(
  MessageCardForm form,
  Map<String, Object?> values,
) {
  final errors = <String, String>{};
  for (final field in form.fields) {
    final error = _fieldError(field, values[field.id]);
    if (error != null) errors[field.id] = error;
  }
  return errors;
}

/// Giá trị gửi lên máy chủ (`{"values": {...}}`): số thành số, ngày thành
/// `YYYY-MM-DD`, ô đánh dấu thành `true` / `false`; ô không bắt buộc để trống
/// thì bỏ qua (riêng chữ gửi chuỗi rỗng).
Map<String, Object?> normalizeMessageCardFormValues(
  MessageCardForm form,
  Map<String, Object?> values,
) {
  final result = <String, Object?>{};
  for (final field in form.fields) {
    final raw = values[field.id];
    switch (field.type) {
      case MessageCardFieldType.text || MessageCardFieldType.textarea:
        result[field.id] = _string(raw).trim();
      case MessageCardFieldType.number:
        final number = parseMessageCardNumber(_string(raw));
        if (number != null) {
          result[field.id] = number == number.roundToDouble()
              ? number.toInt()
              : number;
        }
      case MessageCardFieldType.select:
        final value = _string(raw).trim();
        if (value.isNotEmpty) result[field.id] = value;
      case MessageCardFieldType.date:
        final date = _date(raw);
        if (date != null) result[field.id] = formatMessageCardDate(date);
      case MessageCardFieldType.checkbox:
        result[field.id] = raw == true;
    }
  }
  return result;
}

String? _fieldError(MessageCardFormField field, Object? raw) {
  switch (field.type) {
    case MessageCardFieldType.text || MessageCardFieldType.textarea:
      final text = _string(raw).trim();
      if (text.isEmpty) return field.required ? 'Ô này bắt buộc.' : null;
      if (text.runes.length > field.effectiveMaxLength) {
        return 'Tối đa ${field.effectiveMaxLength} ký tự.';
      }
      return null;
    case MessageCardFieldType.number:
      final text = _string(raw).trim();
      if (text.isEmpty) return field.required ? 'Ô này bắt buộc.' : null;
      final number = parseMessageCardNumber(text);
      if (number == null) return 'Hãy nhập một số.';
      final min = field.min;
      final max = field.max;
      if (min != null && number < min) {
        return 'Nhỏ nhất là ${formatMessageCardNumber(min)}.';
      }
      if (max != null && number > max) {
        return 'Lớn nhất là ${formatMessageCardNumber(max)}.';
      }
      return null;
    case MessageCardFieldType.select:
      final value = _string(raw).trim();
      if (value.isEmpty) return field.required ? 'Hãy chọn một mục.' : null;
      return field.options.any((option) => option.value == value)
          ? null
          : 'Lựa chọn không hợp lệ.';
    case MessageCardFieldType.date:
      final text = raw is DateTime ? 'x' : _string(raw).trim();
      if (text.isEmpty) return field.required ? 'Hãy chọn ngày.' : null;
      return _date(raw) == null ? 'Ngày không hợp lệ.' : null;
    case MessageCardFieldType.checkbox:
      return field.required && raw != true ? 'Cần đánh dấu ô này.' : null;
  }
}

/// Đọc số người dùng gõ: nhận cả `0,5` và `0.5`.
double? parseMessageCardNumber(String value) {
  final text = value.trim().replaceAll(' ', '');
  if (text.isEmpty ||
      ','.allMatches(text).length + '.'.allMatches(text).length > 1) {
    return null;
  }
  final number = double.tryParse(text.replaceAll(',', '.'));
  return number != null && number.isFinite ? number : null;
}

/// Số kiểu Việt Nam: `1.500`, `25,5`, `-0,25` (tối đa 2 chữ số thập phân).
String formatMessageCardNumber(double value) {
  if (!value.isFinite) return '';
  // Số quá lớn để tách nhóm nghìn: dùng dạng mũ cho gọn, không tràn số nguyên.
  if (value.abs() >= 1e15) return value.toStringAsExponential(2);
  final negative = value < 0;
  final rounded = (value.abs() * 100).round() / 100;
  final integer = rounded.truncate();
  final fraction = ((rounded - integer) * 100).round();
  final digits = integer.toString();
  final grouped = StringBuffer();
  for (var index = 0; index < digits.length; index++) {
    if (index > 0 && (digits.length - index) % 3 == 0) grouped.write('.');
    grouped.write(digits[index]);
  }
  var text = grouped.toString();
  if (fraction > 0) {
    final decimals = fraction.toString().padLeft(2, '0');
    text = '$text,${decimals.endsWith('0') ? decimals[0] : decimals}';
  }
  return negative && text != '0' ? '-$text' : text;
}

String formatMessageCardDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

String _string(Object? value) => switch (value) {
  final String text => text,
  final num number => number.toString(),
  _ => '',
};

DateTime? _date(Object? value) => switch (value) {
  final DateTime date => DateTime(date.year, date.month, date.day),
  final String text => parseMessageCardDate(text),
  _ => null,
};

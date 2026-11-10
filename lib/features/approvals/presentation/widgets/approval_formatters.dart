import 'dart:convert';

String two(int value) => value.toString().padLeft(2, '0');

String formatApprovalTime(DateTime time) {
  return '${two(time.day)}/${two(time.month)}/${time.year} '
      '${two(time.hour)}:${two(time.minute)}';
}

/// Tóm tắt ngắn của `payload` (tối đa [maxLength] ký tự) để hiện trong chi tiết.
String approvalPayloadPreview(
  Map<String, Object?> payload, {
  int maxLength = 240,
}) {
  if (payload.isEmpty) return '';
  String text;
  try {
    text = const JsonEncoder.withIndent('  ').convert(payload);
  } on Object {
    text = payload.toString();
  }
  return text.length <= maxLength ? text : '${text.substring(0, maxLength)}…';
}

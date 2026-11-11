import 'dart:convert';

import 'package:flutter/material.dart';

import '../../domain/entities/approval.dart';

/// Màu chữ trạng thái: lỗi dùng màu lỗi của theme (đủ tương phản trên nền).
Color? approvalToneColor(BuildContext context, ApprovalStatusTone tone) {
  return tone == ApprovalStatusTone.error
      ? Theme.of(context).colorScheme.error
      : null;
}

/// Nhãn trạng thái (kèm lý do lỗi) cho trình đọc màn hình và hiển thị.
class ApprovalStatusText extends StatelessWidget {
  const ApprovalStatusText({super.key, required this.approval, this.style});

  final ApprovalRequest approval;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final display = approval.display;
    final text = display.detail == null
        ? display.label
        : '${display.label}: ${display.detail}';
    return Semantics(
      label: 'Trạng thái: $text',
      excludeSemantics: true,
      child: Text(
        text,
        key: const Key('approval_status_text'),
        style: (style ?? const TextStyle()).copyWith(
          color: approvalToneColor(context, display.tone),
          fontWeight: display.tone == ApprovalStatusTone.error
              ? FontWeight.w600
              : null,
        ),
      ),
    );
  }
}

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

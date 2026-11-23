/// Các điều "Cần bạn quyết" trong văn bản kế hoạch (cùng luật tách của IDE:
/// mục có tiêu đề kiểu "Cần bạn quyết", mỗi gạch đầu dòng / số cấp một là một
/// điều, dòng thụt vào nối tiếp, "Không có" thì rỗng).
final class IdePlanDecision {
  const IdePlanDecision({required this.question, this.proposal = ''});

  final String question;

  /// Phần sau "Đề xuất:" (điền sẵn vào ô trả lời).
  final String proposal;
}

final _head = RegExp(r'^(#{1,6})\s+(.+?)\s*#*\s*$');
final _fence = RegExp(r'^\s*(```|~~~)');
final _decisionTitle = RegExp(
  r'^(?:cần bạn quyết|cần quyết|cần xác nhận|câu hỏi|câu hỏi mở|decisions?|open questions?)\b',
  caseSensitive: false,
);
final _otherGroup = RegExp(
  r'^(?:mục tiêu|mục đích|tóm tắt|tổng quan|bối cảnh|goal|summary|overview|tiêu chí|acceptance criteria|đã quyết)\b',
  caseSensitive: false,
);
final _listItem = RegExp(r'^ ?(?:[-*+]|\d{1,2}[.)])\s+(.*)$');
final _none = RegExp(
  r'^(?:không có|không|none|n/?a)[.!]?$',
  caseSensitive: false,
);
final _proposal = RegExp(
  r'(?:\*\*)?(?<![\p{L}\p{N}])Đề xuất(?![\p{L}\p{N}])(?:\*\*)?\s*:\s*(?:\*\*)?\s*',
  caseSensitive: false,
  unicode: true,
);

List<IdePlanDecision> ideParsePlanDecisions(String plan) {
  final lines = plan.replaceAll('\r\n', '\n').split('\n');
  final block = <String>[];
  var inFence = false;
  var inside = false;
  for (final line in lines) {
    if (_fence.hasMatch(line)) inFence = !inFence;
    final h = inFence ? null : _head.firstMatch(line);
    if (h != null && h.group(1)!.length <= 3) {
      final title = h.group(2)!.replaceAll(RegExp(r'[*_`]'), '').trim();
      if (_decisionTitle.hasMatch(title)) {
        inside = true;
        continue;
      }
      if (_otherGroup.hasMatch(title) || h.group(1)!.length <= 2) {
        inside = false;
        continue;
      }
    }
    if (inside) block.add(line);
  }
  final items = <String>[];
  final lead = <String>[];
  for (final raw in block) {
    if (_head.hasMatch(raw)) continue;
    final m = _listItem.firstMatch(raw);
    if (m != null) {
      items.add(m.group(1)!.trim());
    } else if (raw.trim().isNotEmpty && items.isNotEmpty) {
      items[items.length - 1] = '${items.last} ${raw.trim()}';
    } else if (raw.trim().isNotEmpty) {
      lead.add(raw.trim());
    }
  }
  if (items.isEmpty && lead.isNotEmpty) items.add(lead.join(' '));
  return [
    for (final item in items)
      if (item.trim().isNotEmpty && !_none.hasMatch(item.trim()))
        _split(item.trim()),
  ];
}

IdePlanDecision _split(String item) {
  final parts = item.split(_proposal);
  if (parts.length < 2) return IdePlanDecision(question: item);
  return IdePlanDecision(
    question: parts.first.trim(),
    proposal: parts.sublist(1).join(' ').trim(),
  );
}

/// Chèn cú pháp markdown quanh vùng chọn (Dart thuần, dễ test).
library;

enum MyNoteFormat { bold, italic, heading, bullet, checklist, code }

typedef MyNoteFormatResult = ({String text, int start, int end});

/// Áp [format] lên [text] với vùng chọn [start]..[end] (đã chuẩn hoá thứ tự).
MyNoteFormatResult applyMyNoteFormat(
  MyNoteFormat format,
  String text,
  int start,
  int end,
) {
  var from = start < 0 ? text.length : start;
  var to = end < 0 ? text.length : end;
  if (from > to) (from, to) = (to, from);
  from = from.clamp(0, text.length);
  to = to.clamp(0, text.length);
  switch (format) {
    case MyNoteFormat.bold:
      return _wrap(text, from, to, '**');
    case MyNoteFormat.italic:
      return _wrap(text, from, to, '*');
    case MyNoteFormat.code:
      final selected = text.substring(from, to);
      if (selected.contains('\n')) {
        final replacement = '```\n$selected\n```';
        return (
          text: text.replaceRange(from, to, replacement),
          start: from + 4,
          end: from + 4 + selected.length,
        );
      }
      return _wrap(text, from, to, '`');
    case MyNoteFormat.heading:
      return _prefixLines(text, from, to, '## ', _heading2Prefix);
    case MyNoteFormat.bullet:
      return _prefixLines(text, from, to, '- ', _bulletPrefix);
    case MyNoteFormat.checklist:
      return _prefixLines(text, from, to, '- [ ] ', _checkPrefix);
  }
}

MyNoteFormatResult _wrap(String text, int from, int to, String mark) {
  final selected = text.substring(from, to);
  return (
    text: text.replaceRange(from, to, '$mark$selected$mark'),
    start: from + mark.length,
    end: from + mark.length + selected.length,
  );
}

final _headingPrefix = RegExp(r'^#{1,3} ');
final _heading2Prefix = RegExp(r'^## ');
final _bulletPrefix = RegExp(r'^[-*+] (?!\[[ xX]\] )');
final _checkPrefix = RegExp(r'^[-*+] \[[ xX]\] ');

MyNoteFormatResult _prefixLines(
  String text,
  int from,
  int to,
  String prefix,
  RegExp own,
) {
  final lineStart = from == 0 ? 0 : text.lastIndexOf('\n', from - 1) + 1;
  final nextBreak = text.indexOf('\n', to);
  final lineEnd = nextBreak == -1 ? text.length : nextBreak;
  final lines = text.substring(lineStart, lineEnd).split('\n');
  // Bấm lần nữa trên các dòng đã có kiểu này thì gỡ kiểu.
  final remove = lines.every((line) => own.hasMatch(line));
  final others = [_headingPrefix, _bulletPrefix, _checkPrefix];
  final result = <String>[
    for (final line in lines)
      if (remove)
        line.replaceFirst(own, '')
      else
        prefix + _stripOthers(line, others),
  ];
  final block = result.join('\n');
  final newText = text.replaceRange(lineStart, lineEnd, block);
  if (from == to) {
    final delta = result.first.length - lines.first.length;
    final cursor = (from + delta).clamp(lineStart, lineStart + block.length);
    return (text: newText, start: cursor, end: cursor);
  }
  return (text: newText, start: lineStart, end: lineStart + block.length);
}

String _stripOthers(String line, List<RegExp> patterns) {
  for (final pattern in patterns) {
    if (pattern.hasMatch(line)) return line.replaceFirst(pattern, '');
  }
  return line;
}

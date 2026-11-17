/// Thao tác theo dòng cho trình soạn My Note kiểu app Ghi chú iPhone (Dart
/// thuần, không phụ thuộc Flutter). Nội dung vẫn là markdown: các hàm ở đây
/// đọc / đổi dấu đầu dòng (`# `, `- `, `- [ ] `, `1. `, `> `, rào ```` ``` ````)
/// và dấu nội dòng (`**`, `*`, `~~`, `` ` ``) mà không làm hỏng phần chữ.
library;

enum MyNoteBlockStyle {
  title,
  heading,
  subheading,
  body,
  monospace,
  bullet,
  numbered,
  checklist,
  quote,
}

enum MyNoteInlineStyle { bold, italic, strikethrough, code }

/// Văn bản + vùng chọn (độc lập Flutter). selectionStart <= selectionEnd.
final class MyNoteEdit {
  const MyNoteEdit(
    this.text, {
    required this.selectionStart,
    required this.selectionEnd,
  });

  const MyNoteEdit.collapsed(this.text, int offset)
    : selectionStart = offset,
      selectionEnd = offset;

  final String text;
  final int selectionStart;
  final int selectionEnd;

  bool get isCollapsed => selectionStart == selectionEnd;

  @override
  bool operator ==(Object other) =>
      other is MyNoteEdit &&
      other.text == text &&
      other.selectionStart == selectionStart &&
      other.selectionEnd == selectionEnd;

  @override
  int get hashCode => Object.hash(text, selectionStart, selectionEnd);

  @override
  String toString() => 'MyNoteEdit($text, $selectionStart..$selectionEnd)';
}

/// Đoạn [start, end) trong văn bản.
final class MyNoteTextRange {
  const MyNoteTextRange(this.start, this.end);

  final int start;
  final int end;

  bool contains(int offset) => offset >= start && offset < end;

  @override
  bool operator ==(Object other) =>
      other is MyNoteTextRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => '[$start,$end)';
}

/// Kiểu của một dòng đơn lẻ (không biết ngữ cảnh khối mã).
final class MyNoteLineInfo {
  const MyNoteLineInfo({
    required this.style,
    this.indent = 0,
    this.markerLength = 0,
    this.checked = false,
    this.number,
  });

  static const body = MyNoteLineInfo(style: MyNoteBlockStyle.body);

  /// body nếu không có dấu.
  final MyNoteBlockStyle style;

  /// Số khoảng trắng đầu dòng (danh sách lồng, bội 2).
  final int indent;

  /// Số ký tự dấu (gồm thụt + khoảng trắng sau dấu): phần sẽ ẩn / thay widget.
  final int markerLength;

  /// Checklist đã tick.
  final bool checked;

  /// Số của danh sách đánh số.
  final int? number;

  bool get isList =>
      style == MyNoteBlockStyle.bullet ||
      style == MyNoteBlockStyle.numbered ||
      style == MyNoteBlockStyle.checklist;

  @override
  bool operator ==(Object other) =>
      other is MyNoteLineInfo &&
      other.style == style &&
      other.indent == indent &&
      other.markerLength == markerLength &&
      other.checked == checked &&
      other.number == number;

  @override
  int get hashCode => Object.hash(style, indent, markerLength, checked, number);

  @override
  String toString() =>
      'Line($style, indent=$indent, marker=$markerLength, '
      'checked=$checked, number=$number)';
}

final _headingRe = RegExp(r'^(#{1,3}) ');
final _checklistRe = RegExp(r'^( *)[-*+] \[([ xX])\](?: |$)');
final _bulletRe = RegExp(r'^( *)[-*+] ');
final _numberedRe = RegExp(r'^( *)(\d{1,9})[.)] ');
final _quoteRe = RegExp(r'^( *)>(?: |$)');

/// Phân tích dấu đầu một dòng (không tính khối mã: xem [parseMyNoteLines]).
MyNoteLineInfo parseMyNoteLine(String line) {
  if (line.isEmpty) return MyNoteLineInfo.body;
  final first = line.codeUnitAt(0);
  if (first == 0x23 /* # */ ) {
    final match = _headingRe.firstMatch(line);
    if (match == null) return MyNoteLineInfo.body;
    final level = match.group(1)!.length;
    return MyNoteLineInfo(
      style: switch (level) {
        1 => MyNoteBlockStyle.title,
        2 => MyNoteBlockStyle.heading,
        _ => MyNoteBlockStyle.subheading,
      },
      markerLength: match.end,
    );
  }
  if (first != 0x20 && first != 0x2D && first != 0x2A && first != 0x2B) {
    if (first == 0x3E /* > */ ) return _parseQuote(line);
    if (first >= 0x30 && first <= 0x39) return _parseNumbered(line);
    return MyNoteLineInfo.body;
  }
  final check = _checklistRe.firstMatch(line);
  if (check != null) {
    return MyNoteLineInfo(
      style: MyNoteBlockStyle.checklist,
      indent: check.group(1)!.length,
      markerLength: check.end,
      checked: check.group(2) != ' ',
    );
  }
  final bullet = _bulletRe.firstMatch(line);
  if (bullet != null) {
    return MyNoteLineInfo(
      style: MyNoteBlockStyle.bullet,
      indent: bullet.group(1)!.length,
      markerLength: bullet.end,
    );
  }
  final numbered = _parseNumbered(line);
  if (numbered.style != MyNoteBlockStyle.body) return numbered;
  return _parseQuote(line);
}

MyNoteLineInfo _parseNumbered(String line) {
  final match = _numberedRe.firstMatch(line);
  if (match == null) return MyNoteLineInfo.body;
  return MyNoteLineInfo(
    style: MyNoteBlockStyle.numbered,
    indent: match.group(1)!.length,
    markerLength: match.end,
    number: int.parse(match.group(2)!),
  );
}

MyNoteLineInfo _parseQuote(String line) {
  final match = _quoteRe.firstMatch(line);
  if (match == null) return MyNoteLineInfo.body;
  return MyNoteLineInfo(
    style: MyNoteBlockStyle.quote,
    indent: match.group(1)!.length,
    markerLength: match.end,
  );
}

/// Một dòng của văn bản kèm vị trí và ngữ cảnh khối mã.
final class MyNoteLine {
  const MyNoteLine({
    required this.index,
    required this.start,
    required this.end,
    required this.text,
    required this.info,
    this.isFence = false,
    this.inCode = false,
  });

  final int index;

  /// Vị trí ký tự đầu dòng trong văn bản.
  final int start;

  /// Vị trí ngay sau ký tự cuối dòng (trước `\n`).
  final int end;
  final String text;

  /// Dòng trong khối mã / dòng rào: style monospace, markerLength 0.
  final MyNoteLineInfo info;

  /// Dòng rào ```` ``` ```` mở hoặc đóng khối mã.
  final bool isFence;

  /// Dòng nằm giữa hai rào (nội dung mã).
  final bool inCode;

  bool get isCode => isFence || inCode;
}

const _codeLineInfo = MyNoteLineInfo(style: MyNoteBlockStyle.monospace);

bool _isFence(String line) => line.trimLeft().startsWith('```');

/// Tách [text] thành dòng, biết khối mã (rào chưa đóng thì mã tới cuối).
List<MyNoteLine> parseMyNoteLines(String text) {
  final lines = <MyNoteLine>[];
  var start = 0;
  var inCode = false;
  var index = 0;
  while (true) {
    final next = text.indexOf('\n', start);
    final end = next == -1 ? text.length : next;
    final line = text.substring(start, end);
    if (_isFence(line)) {
      lines.add(
        MyNoteLine(
          index: index,
          start: start,
          end: end,
          text: line,
          info: _codeLineInfo,
          isFence: true,
        ),
      );
      inCode = !inCode;
    } else {
      lines.add(
        MyNoteLine(
          index: index,
          start: start,
          end: end,
          text: line,
          info: inCode ? _codeLineInfo : parseMyNoteLine(line),
          inCode: inCode,
        ),
      );
    }
    index++;
    if (next == -1) break;
    start = next + 1;
  }
  return lines;
}

/// Chỉ số dòng chứa [offset] (nhị phân trên danh sách đã sắp).
int myNoteLineIndexAt(List<MyNoteLine> lines, int offset) {
  var low = 0;
  var high = lines.length - 1;
  while (low < high) {
    final mid = (low + high + 1) >> 1;
    if (lines[mid].start <= offset) {
      low = mid;
    } else {
      high = mid - 1;
    }
  }
  return low;
}

int _lineStartOf(String text, int offset) =>
    offset <= 0 ? 0 : text.lastIndexOf('\n', offset - 1) + 1;

int _lineEndOf(String text, int offset) {
  final next = text.indexOf('\n', offset);
  return next == -1 ? text.length : next;
}

MyNoteEdit _normalize(MyNoteEdit edit) {
  final length = edit.text.length;
  var start = edit.selectionStart.clamp(0, length);
  var end = edit.selectionEnd.clamp(0, length);
  if (start > end) (start, end) = (end, start);
  if (start == edit.selectionStart && end == edit.selectionEnd) return edit;
  return MyNoteEdit(edit.text, selectionStart: start, selectionEnd: end);
}

/// Một chỗ thay [start, end) bằng [replacement].
final class _Replacement {
  const _Replacement(this.start, this.end, this.replacement);

  final int start;
  final int end;
  final String replacement;
}

/// Áp các chỗ thay (không chồng nhau) và dời vùng chọn theo. Vị trí nằm trong
/// đoạn bị thay thì dời ra sau phần mới.
MyNoteEdit _applyReplacements(MyNoteEdit edit, List<_Replacement> list) {
  if (list.isEmpty) return edit;
  final sorted = [...list]..sort((a, b) => b.start.compareTo(a.start));
  var text = edit.text;
  var selStart = edit.selectionStart;
  var selEnd = edit.selectionEnd;
  int map(int p, _Replacement r) {
    if (p < r.start) return p;
    if (p >= r.end) return p + r.replacement.length - (r.end - r.start);
    return r.start + r.replacement.length;
  }

  for (final r in sorted) {
    text = text.replaceRange(r.start, r.end, r.replacement);
    selStart = map(selStart, r);
    selEnd = map(selEnd, r);
  }
  if (selStart > selEnd) selStart = selEnd;
  return MyNoteEdit(text, selectionStart: selStart, selectionEnd: selEnd);
}

/// Các dòng chịu tác động của vùng chọn. Vùng chọn kết thúc đúng đầu dòng thì
/// không tính dòng đó (giống chọn cả dòng bằng kéo).
List<MyNoteLine> _selectedLines(List<MyNoteLine> lines, MyNoteEdit edit) {
  final first = myNoteLineIndexAt(lines, edit.selectionStart);
  var last = myNoteLineIndexAt(lines, edit.selectionEnd);
  if (last > first && lines[last].start == edit.selectionEnd) last--;
  return lines.sublist(first, last + 1);
}

String _markerFor(MyNoteBlockStyle style, int indent, int number) {
  final pad = ' ' * indent;
  return switch (style) {
    MyNoteBlockStyle.title => '# ',
    MyNoteBlockStyle.heading => '## ',
    MyNoteBlockStyle.subheading => '### ',
    MyNoteBlockStyle.bullet => '$pad- ',
    MyNoteBlockStyle.numbered => '$pad$number. ',
    MyNoteBlockStyle.checklist => '$pad- [ ] ',
    MyNoteBlockStyle.quote => '$pad> ',
    MyNoteBlockStyle.body || MyNoteBlockStyle.monospace => '',
  };
}

const _toggleStyles = {
  MyNoteBlockStyle.bullet,
  MyNoteBlockStyle.numbered,
  MyNoteBlockStyle.checklist,
  MyNoteBlockStyle.quote,
};

/// Áp kiểu dòng cho mọi dòng trong vùng chọn. Chọn lại đúng kiểu danh sách /
/// quote / checklist đang có thì bỏ về body; monospace bọc các dòng bằng rào
/// ```` ``` ```` (bỏ rào nếu đã ở trong khối mã).
MyNoteEdit setMyNoteBlockStyle(MyNoteEdit edit, MyNoteBlockStyle style) {
  var current = _normalize(edit);
  var lines = parseMyNoteLines(current.text);
  var selected = _selectedLines(lines, current);

  // Đang trong khối mã: gỡ rào khối đó trước.
  final codeLine = selected.where((line) => line.isCode).firstOrNull;
  if (codeLine != null) {
    current = _unwrapCodeBlock(current, lines, codeLine.index);
    if (style == MyNoteBlockStyle.monospace) return current;
    lines = parseMyNoteLines(current.text);
    selected = _selectedLines(lines, current);
  }

  if (style == MyNoteBlockStyle.monospace) {
    final first = selected.first;
    final last = selected.last;
    final strip = [
      for (final line in selected)
        if (line.info.markerLength > 0)
          _Replacement(line.start, line.start + line.info.markerLength, ''),
    ];
    final stripped = _applyReplacements(current, strip);
    final shift = strip.fold<int>(0, (sum, r) => sum + r.end - r.start);
    final lastEnd = last.end - shift;
    final wrapped = stripped.text
        .replaceRange(lastEnd, lastEnd, '\n```')
        .replaceRange(first.start, first.start, '```\n');
    // Con trỏ ở lại trong khối (sau rào mở, trước rào đóng).
    int inside(int p) =>
        (p < first.start
            ? first.start
            : p > lastEnd
            ? lastEnd
            : p) +
        4;
    return MyNoteEdit(
      wrapped,
      selectionStart: inside(stripped.selectionStart),
      selectionEnd: inside(stripped.selectionEnd),
    );
  }

  final removeToBody =
      _toggleStyles.contains(style) &&
      selected.every((line) => line.info.style == style);
  final target = removeToBody ? MyNoteBlockStyle.body : style;

  var number = 1;
  if (target == MyNoteBlockStyle.numbered) {
    final first = selected.first;
    final indent =
        first.info.isList || first.info.style == MyNoteBlockStyle.quote
        ? first.info.indent
        : 0;
    for (var i = first.index - 1; i >= 0; i--) {
      final info = lines[i].info;
      if (info.style == MyNoteBlockStyle.numbered && info.indent == indent) {
        number = (info.number ?? 0) + 1;
        break;
      }
      if (!(info.isList && info.indent > indent)) break;
    }
  }

  final replacements = <_Replacement>[];
  for (final line in selected) {
    final info = line.info;
    final keepIndent = info.isList || info.style == MyNoteBlockStyle.quote
        ? info.indent
        : 0;
    final marker = _markerFor(target, keepIndent, number);
    if (target == MyNoteBlockStyle.numbered) number++;
    final old = line.text.substring(0, info.markerLength);
    if (old == marker) continue;
    replacements.add(
      _Replacement(line.start, line.start + info.markerLength, marker),
    );
  }
  return _applyReplacements(current, replacements);
}

/// Gỡ hai dòng rào của khối mã chứa dòng [lineIndex] (rào ghép cặp theo thứ
/// tự; rào chưa đóng thì chỉ gỡ rào mở).
MyNoteEdit _unwrapCodeBlock(
  MyNoteEdit edit,
  List<MyNoteLine> lines,
  int lineIndex,
) {
  final fences = [
    for (final line in lines)
      if (line.isFence) line.index,
  ];
  for (var i = 0; i < fences.length; i += 2) {
    final open = fences[i];
    final close = i + 1 < fences.length ? fences[i + 1] : null;
    if (lineIndex < open || (close != null && lineIndex > close)) continue;
    final text = edit.text;
    final replacements = <_Replacement>[];
    if (close != null) {
      final line = lines[close];
      // Bỏ cả "\n" ngay trước dòng rào đóng.
      replacements.add(_Replacement(line.start - 1, line.end, ''));
    }
    final opening = lines[open];
    final removeEnd = opening.end < text.length ? opening.end + 1 : opening.end;
    replacements.add(_Replacement(opening.start, removeEnd, ''));
    return _applyReplacements(edit, replacements);
  }
  return edit;
}

/// Nút ô tick trên thanh công cụ.
MyNoteEdit toggleMyNoteChecklist(MyNoteEdit edit) =>
    setMyNoteBlockStyle(edit, MyNoteBlockStyle.checklist);

/// Bấm ô tick trên dòng bắt đầu ở [lineStart]; giữ nguyên vùng chọn.
MyNoteEdit toggleMyNoteCheckedAt(MyNoteEdit edit, int lineStart) {
  final text = edit.text;
  if (lineStart < 0 || lineStart > text.length) return edit;
  if (lineStart > 0 && text.codeUnitAt(lineStart - 1) != 0x0A) return edit;
  final lines = parseMyNoteLines(text);
  final line = lines[myNoteLineIndexAt(lines, lineStart)];
  if (line.info.style != MyNoteBlockStyle.checklist) return edit;
  final at = line.start + line.info.indent + 3;
  final mark = line.info.checked ? ' ' : 'x';
  return MyNoteEdit(
    text.replaceRange(at, at + 1, mark),
    selectionStart: edit.selectionStart,
    selectionEnd: edit.selectionEnd,
  );
}

// ---------------------------------------------------------------- nội dòng

/// Một đoạn định dạng nội dòng, vị trí tương đối trong dòng. [start]..[end]
/// gồm cả dấu; dấu dài [markLength] ở hai đầu.
final class MyNoteInlineSpan {
  const MyNoteInlineSpan(this.style, this.start, this.end, this.markLength);

  final MyNoteInlineStyle style;
  final int start;
  final int end;
  final int markLength;

  int get contentStart => start + markLength;
  int get contentEnd => end - markLength;

  @override
  String toString() => '$style[$start,$end)';
}

final _codeSpanRe = RegExp(r'`[^`\n]+`');
final _boldRe = RegExp(r'\*\*(?=\S)(.+?)(?<=\S)\*\*');
final _strikeRe = RegExp(r'~~(?=\S)(.+?)(?<=\S)~~');
final _italicStarRe = RegExp(
  r'(?<![*\p{L}\p{N}_])\*(?=[^\s*])(.+?)(?<=[^\s*])\*(?![*\p{L}\p{N}_])',
  unicode: true,
);
final _italicUnderscoreRe = RegExp(
  r'(?<![\p{L}\p{N}_])_(?=[^\s_])(.+?)(?<=[^\s_])_(?![\p{L}\p{N}_])',
  unicode: true,
);

/// Tìm các đoạn đậm / nghiêng / gạch / mã trong một dòng. Trong mã nội dòng
/// không phân tích tiếp.
List<MyNoteInlineSpan> parseMyNoteInlineSpans(String line) {
  if (line.length < 2) return const [];
  if (!line.contains('*') &&
      !line.contains('_') &&
      !line.contains('~') &&
      !line.contains('`')) {
    return const [];
  }
  final spans = <MyNoteInlineSpan>[];
  var masked = line;
  for (final match in _codeSpanRe.allMatches(line)) {
    spans.add(
      MyNoteInlineSpan(MyNoteInlineStyle.code, match.start, match.end, 1),
    );
    masked = masked.replaceRange(
      match.start,
      match.end,
      '\u0000' * (match.end - match.start),
    );
  }
  void collect(RegExp re, MyNoteInlineStyle style, int mark) {
    for (final match in re.allMatches(masked)) {
      if (match.group(0)!.contains('\u0000')) continue;
      spans.add(MyNoteInlineSpan(style, match.start, match.end, mark));
    }
  }

  collect(_boldRe, MyNoteInlineStyle.bold, 2);
  collect(_strikeRe, MyNoteInlineStyle.strikethrough, 2);
  // Che phần đậm để `*` của nó không bị hiểu là nghiêng.
  var italicSource = masked;
  for (final span in spans) {
    if (span.style != MyNoteInlineStyle.bold) continue;
    italicSource = italicSource
        .replaceRange(span.start, span.start + 2, '\u0001\u0001')
        .replaceRange(span.end - 2, span.end, '\u0001\u0001');
  }
  for (final re in [_italicStarRe, _italicUnderscoreRe]) {
    for (final match in re.allMatches(italicSource)) {
      if (match.group(0)!.contains('\u0000')) continue;
      spans.add(
        MyNoteInlineSpan(MyNoteInlineStyle.italic, match.start, match.end, 1),
      );
    }
  }
  spans.sort((a, b) => a.start.compareTo(b.start));
  return spans;
}

String _inlineMark(MyNoteInlineStyle style) => switch (style) {
  MyNoteInlineStyle.bold => '**',
  MyNoteInlineStyle.italic => '*',
  MyNoteInlineStyle.strikethrough => '~~',
  MyNoteInlineStyle.code => '`',
};

/// Kiểu nội dòng đang bật tại [offset] (để tô nút trên thanh công cụ).
Set<MyNoteInlineStyle> myNoteInlineStylesAt(String text, int offset) {
  final at = offset.clamp(0, text.length);
  final lineStart = _lineStartOf(text, at);
  final line = text.substring(lineStart, _lineEndOf(text, at));
  final relative = at - lineStart;
  return {
    for (final span in parseMyNoteInlineSpans(line))
      if (relative >= span.contentStart && relative <= span.contentEnd)
        span.style,
  };
}

/// Bật / tắt đậm `**`, nghiêng `*`, gạch `~~`, mã `` ` ``. Vùng chọn rỗng:
/// đang trong đoạn kiểu đó thì gỡ dấu, không thì chèn cặp dấu và đặt con trỏ
/// giữa. Vùng chọn nhiều dòng: bọc / gỡ từng dòng.
MyNoteEdit toggleMyNoteInlineStyle(MyNoteEdit edit, MyNoteInlineStyle style) {
  final current = _normalize(edit);
  final text = current.text;
  final mark = _inlineMark(style);
  final m = mark.length;
  final lines = parseMyNoteLines(text);

  if (current.isCollapsed) {
    final at = current.selectionStart;
    // Cặp dấu rỗng vừa chèn: bấm lại thì gỡ.
    if (at >= m &&
        at + m <= text.length &&
        text.substring(at - m, at) == mark &&
        text.substring(at, at + m) == mark) {
      return _applyReplacements(current, [_Replacement(at - m, at + m, '')]);
    }
    final line = lines[myNoteLineIndexAt(lines, at)];
    final span = _spanAround(line, at - line.start, style);
    if (span != null) return _unwrap(current, line.start, span);
    return MyNoteEdit.collapsed(
      text.replaceRange(at, at, '$mark$mark'),
      at + m,
    );
  }

  final selStart = current.selectionStart;
  final selEnd = current.selectionEnd;

  // Một dòng, dấu nằm ngay ngoài vùng chọn: gỡ.
  if (selStart >= m &&
      selEnd + m <= text.length &&
      text.substring(selStart - m, selStart) == mark &&
      text.substring(selEnd, selEnd + m) == mark &&
      !text.substring(selStart, selEnd).contains('\n')) {
    final removed = _applyReplacements(current, [
      _Replacement(selEnd, selEnd + m, ''),
      _Replacement(selStart - m, selStart, ''),
    ]);
    return MyNoteEdit(
      removed.text,
      selectionStart: selStart - m,
      selectionEnd: selEnd - m,
    );
  }

  final segments = <MyNoteTextRange>[];
  final lineOf = <MyNoteLine>[];
  for (final line in _selectedLines(lines, current)) {
    if (line.isCode) continue;
    final from = selStart > line.start + line.info.markerLength
        ? selStart
        : line.start + line.info.markerLength;
    final to = selEnd < line.end ? selEnd : line.end;
    if (to <= from) continue;
    // Bỏ khoảng trắng hai đầu để dấu bám vào chữ.
    var s = from;
    var e = to;
    while (s < e && _isSpace(text.codeUnitAt(s))) {
      s++;
    }
    while (e > s && _isSpace(text.codeUnitAt(e - 1))) {
      e--;
    }
    if (e <= s) continue;
    segments.add(MyNoteTextRange(s, e));
    lineOf.add(line);
  }
  if (segments.isEmpty) return current;

  // Mọi đoạn đều đã nằm trong kiểu này: gỡ.
  final enclosing = <(MyNoteLine, MyNoteInlineSpan)>[];
  for (var i = 0; i < segments.length; i++) {
    final line = lineOf[i];
    final seg = segments[i];
    MyNoteInlineSpan? found;
    for (final span in parseMyNoteInlineSpans(line.text)) {
      if (span.style != style) continue;
      final spanStart = line.start + span.start;
      final spanEnd = line.start + span.end;
      if (seg.start >= spanStart && seg.end <= spanEnd) {
        found = span;
        break;
      }
    }
    if (found == null) break;
    enclosing.add((line, found));
  }
  if (enclosing.length == segments.length) {
    final replacements = <_Replacement>[];
    for (final (line, span) in enclosing) {
      replacements
        ..add(
          _Replacement(line.start + span.contentEnd, line.start + span.end, ''),
        )
        ..add(
          _Replacement(
            line.start + span.start,
            line.start + span.contentStart,
            '',
          ),
        );
    }
    return _applyReplacements(current, _dedupe(replacements));
  }

  // Bọc từng đoạn; vùng chọn bao trọn chữ đã bọc (không gồm dấu).
  var newText = text;
  var newStart = selStart;
  var newEnd = selEnd;
  for (final seg in segments.reversed) {
    newText = newText
        .replaceRange(seg.end, seg.end, mark)
        .replaceRange(seg.start, seg.start, mark);
    if (newEnd >= seg.end) newEnd += 2 * m;
    if (newStart > seg.start) newStart += m;
  }
  if (segments.length == 1) {
    newStart = segments.first.start + m;
    newEnd = segments.first.end + m;
  }
  return MyNoteEdit(newText, selectionStart: newStart, selectionEnd: newEnd);
}

List<_Replacement> _dedupe(List<_Replacement> list) {
  final seen = <int>{};
  return [
    for (final r in list)
      if (seen.add(r.start)) r,
  ];
}

bool _isSpace(int unit) => unit == 0x20 || unit == 0x09;

MyNoteInlineSpan? _spanAround(
  MyNoteLine line,
  int relative,
  MyNoteInlineStyle style,
) {
  if (line.isCode) return null;
  for (final span in parseMyNoteInlineSpans(line.text)) {
    if (span.style == style &&
        relative >= span.contentStart &&
        relative <= span.contentEnd) {
      return span;
    }
  }
  return null;
}

MyNoteEdit _unwrap(MyNoteEdit edit, int lineStart, MyNoteInlineSpan span) {
  return _applyReplacements(edit, [
    _Replacement(lineStart + span.contentEnd, lineStart + span.end, ''),
    _Replacement(lineStart + span.start, lineStart + span.contentStart, ''),
  ]);
}

/// Kiểu dòng chứa [offset] (tính cả khối mã). Dòng đầu không dấu là title.
MyNoteBlockStyle myNoteBlockStyleAt(String text, int offset) {
  final lines = parseMyNoteLines(text);
  final line = lines[myNoteLineIndexAt(lines, offset.clamp(0, text.length))];
  if (line.index == 0 && line.info.style == MyNoteBlockStyle.body) {
    return MyNoteBlockStyle.title;
  }
  return line.info.style;
}

// ------------------------------------------------------ Enter / Backspace

/// [after] = [before] + đúng một "\n" vừa gõ tại con trỏ. Dòng danh sách /
/// checklist / quote → dòng mới cùng dấu (số +1, checklist chưa tick, giữ
/// thụt); dòng danh sách rỗng → bỏ dấu, không thêm dòng. Trả null nếu không
/// can thiệp.
MyNoteEdit? myNoteHandleNewline(MyNoteEdit before, MyNoteEdit after) {
  final b = _normalize(before);
  final a = _normalize(after);
  if (!a.isCollapsed) return null;
  final cursor = a.selectionStart;
  if (cursor != b.selectionStart + 1) return null;
  if (a.text.length !=
      b.text.length - (b.selectionEnd - b.selectionStart) + 1) {
    return null;
  }
  if (a.text.codeUnitAt(cursor - 1) != 0x0A) return null;
  if (!a.text.startsWith(b.text.substring(0, b.selectionStart)) ||
      !a.text.endsWith(b.text.substring(b.selectionEnd))) {
    return null;
  }

  final at = b.selectionStart;
  final lines = parseMyNoteLines(b.text);
  final line = lines[myNoteLineIndexAt(lines, at)];
  final info = line.info;
  if (line.isCode) return null;
  if (!info.isList && info.style != MyNoteBlockStyle.quote) return null;
  final markerEnd = line.start + info.markerLength;
  if (at < markerEnd) return null;

  final content = line.text.substring(info.markerLength);
  if (content.trim().isEmpty && b.isCollapsed) {
    // Dòng chỉ có dấu: thoát danh sách, giữ con trỏ trên dòng đó.
    final text = b.text.replaceRange(line.start, line.end, '');
    return MyNoteEdit.collapsed(text, line.start);
  }

  final marker = switch (info.style) {
    MyNoteBlockStyle.numbered =>
      '${' ' * info.indent}${(info.number ?? 0) + 1}'
          '${line.text[info.indent + '${info.number}'.length]} ',
    MyNoteBlockStyle.checklist =>
      '${' ' * info.indent}${line.text[info.indent]} [ ] ',
    MyNoteBlockStyle.bullet => line.text.substring(0, info.indent + 2),
    _ => '${' ' * info.indent}> ',
  };
  var text = a.text.replaceRange(cursor, cursor, marker);
  final result = cursor + marker.length;
  if (info.style == MyNoteBlockStyle.numbered) {
    text = _renumberAfter(text, result, info.indent, (info.number ?? 0) + 2);
  }
  return MyNoteEdit.collapsed(text, result);
}

/// Đánh lại số các dòng đánh số cùng thụt nằm liền sau dòng chứa [offset].
String _renumberAfter(String text, int offset, int indent, int next) {
  final lines = parseMyNoteLines(text);
  final index = myNoteLineIndexAt(lines, offset);
  final replacements = <_Replacement>[];
  var number = next;
  for (var i = index + 1; i < lines.length; i++) {
    final line = lines[i];
    final info = line.info;
    if (line.isCode) break;
    if (info.style == MyNoteBlockStyle.numbered && info.indent == indent) {
      final digits = '${info.number}';
      if (info.number != number) {
        final s = line.start + indent;
        replacements.add(_Replacement(s, s + digits.length, '$number'));
      }
      number++;
      continue;
    }
    if (info.isList && info.indent > indent) continue;
    break;
  }
  if (replacements.isEmpty) return text;
  return _applyReplacements(MyNoteEdit.collapsed(text, 0), replacements).text;
}

/// Xoá lùi khi con trỏ đứng ngay sau dấu đầu dòng (danh sách, checklist,
/// quote, heading) → bỏ cả dấu, giữ chữ. Null nếu không can thiệp.
MyNoteEdit? myNoteHandleBackspace(MyNoteEdit before, MyNoteEdit after) {
  final b = _normalize(before);
  final a = _normalize(after);
  if (!b.isCollapsed || !a.isCollapsed) return null;
  final cursor = b.selectionStart;
  if (cursor == 0 || a.selectionStart != cursor - 1) return null;
  if (a.text.length != b.text.length - 1) return null;
  if (a.text != b.text.substring(0, cursor - 1) + b.text.substring(cursor)) {
    return null;
  }
  final lines = parseMyNoteLines(b.text);
  final line = lines[myNoteLineIndexAt(lines, cursor)];
  if (line.isCode || line.info.markerLength == 0) return null;
  if (cursor != line.start + line.info.markerLength) return null;
  return MyNoteEdit.collapsed(
    b.text.replaceRange(line.start, cursor, ''),
    line.start,
  );
}

/// Các dấu đầu dòng [start, end) sẽ bị ẩn / thay widget, để controller dời
/// con trỏ ra khỏi.
List<MyNoteTextRange> myNoteHiddenLineMarkers(String text) =>
    myNoteHiddenLineMarkersOf(parseMyNoteLines(text));

List<MyNoteTextRange> myNoteHiddenLineMarkersOf(List<MyNoteLine> lines) => [
  for (final line in lines)
    if (!line.isCode && line.info.markerLength > 0)
      MyNoteTextRange(line.start, line.start + line.info.markerLength),
];

// -------------------------------------------------------------------- tag

const myNoteMaxInlineTags = 20;
const myNoteMaxTagRunes = 40;

final _tagRe = RegExp(r'(?<=^|\s)#([\p{L}\p{M}\p{N}_-]+)', unicode: true);

/// #tag ở đầu chuỗi hoặc sau khoảng trắng / xuống dòng; không tính trong khối
/// mã, mã nội dòng, URL. Chuẩn hoá giống máy chủ: chữ thường, bỏ trùng, giữ
/// thứ tự, bỏ tag dài hơn 40 ký tự, tối đa 20 tag.
List<String> extractMyNoteInlineTags(String text) {
  if (!text.contains('#')) return const [];
  final tags = <String>[];
  final seen = <String>{};
  for (final line in parseMyNoteLines(text)) {
    if (line.isCode || !line.text.contains('#')) continue;
    var source = line.text;
    for (final match in _codeSpanRe.allMatches(source)) {
      source = source.replaceRange(
        match.start,
        match.end,
        ' ' * (match.end - match.start),
      );
    }
    for (final match in _tagRe.allMatches(source)) {
      final tag = match.group(1)!.toLowerCase();
      if (tag.runes.length > myNoteMaxTagRunes) continue;
      if (!seen.add(tag)) continue;
      tags.add(tag);
      if (tags.length >= myNoteMaxInlineTags) return tags;
    }
  }
  return tags;
}

/// Vị trí [start, end) các #tag trong một dòng (để tô màu), cùng luật với
/// [extractMyNoteInlineTags] nhưng không chuẩn hoá.
List<MyNoteTextRange> myNoteTagRangesInLine(String line) {
  if (!line.contains('#')) return const [];
  return [
    for (final match in _tagRe.allMatches(line))
      MyNoteTextRange(match.start, match.end),
  ];
}

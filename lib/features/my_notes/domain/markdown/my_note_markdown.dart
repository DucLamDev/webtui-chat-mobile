/// Bộ phân tích markdown rút gọn cho My Note (Dart thuần, không phụ thuộc
/// Flutter): tiêu đề `#`..`###`, đậm, nghiêng, mã nội dòng, khối mã, danh
/// sách gạch đầu dòng / đánh số, ô tick và liên kết.
library;

/// Đoạn chữ trong một dòng.
sealed class MarkdownInline {
  const MarkdownInline();
}

final class MarkdownText extends MarkdownInline {
  const MarkdownText(this.text, {this.bold = false, this.italic = false});

  final String text;
  final bool bold;
  final bool italic;

  @override
  bool operator ==(Object other) =>
      other is MarkdownText &&
      other.text == text &&
      other.bold == bold &&
      other.italic == italic;

  @override
  int get hashCode => Object.hash(text, bold, italic);

  @override
  String toString() => 'Text($text,b=$bold,i=$italic)';
}

final class MarkdownCode extends MarkdownInline {
  const MarkdownCode(this.text);

  final String text;

  @override
  bool operator ==(Object other) => other is MarkdownCode && other.text == text;

  @override
  int get hashCode => text.hashCode;

  @override
  String toString() => 'Code($text)';
}

final class MarkdownLink extends MarkdownInline {
  const MarkdownLink(this.label, this.url);

  final String label;
  final String url;

  @override
  bool operator ==(Object other) =>
      other is MarkdownLink && other.label == label && other.url == url;

  @override
  int get hashCode => Object.hash(label, url);

  @override
  String toString() => 'Link($label,$url)';
}

/// Khối nội dung.
sealed class MarkdownBlock {
  const MarkdownBlock();
}

final class MarkdownHeading extends MarkdownBlock {
  const MarkdownHeading(this.level, this.inlines);

  final int level;
  final List<MarkdownInline> inlines;
}

final class MarkdownParagraph extends MarkdownBlock {
  const MarkdownParagraph(this.inlines);

  final List<MarkdownInline> inlines;
}

final class MarkdownBullet extends MarkdownBlock {
  const MarkdownBullet(this.inlines, {this.depth = 0});

  final List<MarkdownInline> inlines;
  final int depth;
}

final class MarkdownNumbered extends MarkdownBlock {
  const MarkdownNumbered(this.number, this.inlines, {this.depth = 0});

  final int number;
  final List<MarkdownInline> inlines;
  final int depth;
}

final class MarkdownCheckbox extends MarkdownBlock {
  const MarkdownCheckbox(this.checked, this.inlines, {this.depth = 0});

  final bool checked;
  final List<MarkdownInline> inlines;
  final int depth;
}

final class MarkdownCodeBlock extends MarkdownBlock {
  const MarkdownCodeBlock(this.code);

  final String code;
}

final _headingRe = RegExp(r'^(#{1,3})\s+(.*)$');
final _checkboxRe = RegExp(r'^(\s*)[-*+]\s+\[([ xX])\]\s+(.*)$');
final _bulletRe = RegExp(r'^(\s*)[-*+]\s+(.*)$');
final _numberedRe = RegExp(r'^(\s*)(\d{1,9})[.)]\s+(.*)$');

int _depth(String indent) =>
    (indent.replaceAll('\t', '  ').length ~/ 2).clamp(0, 4);

/// Phân tích [source] thành danh sách khối. Dòng trống chỉ ngăn các đoạn.
List<MarkdownBlock> parseMyNoteMarkdown(String source) {
  final blocks = <MarkdownBlock>[];
  final lines = source.replaceAll('\r\n', '\n').split('\n');
  final paragraph = <String>[];

  void flushParagraph() {
    if (paragraph.isEmpty) return;
    blocks.add(MarkdownParagraph(parseMyNoteInline(paragraph.join('\n'))));
    paragraph.clear();
  }

  var index = 0;
  while (index < lines.length) {
    final line = lines[index];
    final trimmed = line.trimLeft();
    if (trimmed.startsWith('```')) {
      flushParagraph();
      final code = <String>[];
      index++;
      while (index < lines.length &&
          !lines[index].trimLeft().startsWith('```')) {
        code.add(lines[index]);
        index++;
      }
      // Bỏ qua dòng đóng (nếu có); khối chưa đóng vẫn hiện hết phần còn lại.
      index++;
      blocks.add(MarkdownCodeBlock(code.join('\n')));
      continue;
    }
    index++;
    if (line.trim().isEmpty) {
      flushParagraph();
      continue;
    }
    final heading = _headingRe.firstMatch(line);
    if (heading != null) {
      flushParagraph();
      blocks.add(
        MarkdownHeading(
          heading.group(1)!.length,
          parseMyNoteInline(heading.group(2)!.trim()),
        ),
      );
      continue;
    }
    final checkbox = _checkboxRe.firstMatch(line);
    if (checkbox != null) {
      flushParagraph();
      blocks.add(
        MarkdownCheckbox(
          checkbox.group(2)!.toLowerCase() == 'x',
          parseMyNoteInline(checkbox.group(3)!),
          depth: _depth(checkbox.group(1)!),
        ),
      );
      continue;
    }
    final bullet = _bulletRe.firstMatch(line);
    if (bullet != null) {
      flushParagraph();
      blocks.add(
        MarkdownBullet(
          parseMyNoteInline(bullet.group(2)!),
          depth: _depth(bullet.group(1)!),
        ),
      );
      continue;
    }
    final numbered = _numberedRe.firstMatch(line);
    if (numbered != null) {
      flushParagraph();
      blocks.add(
        MarkdownNumbered(
          int.parse(numbered.group(2)!),
          parseMyNoteInline(numbered.group(3)!),
          depth: _depth(numbered.group(1)!),
        ),
      );
      continue;
    }
    paragraph.add(line);
  }
  flushParagraph();
  return blocks;
}

final _linkRe = RegExp(r'^\[([^\]\n]+)\]\((https?://[^\s)]+)\)');
final _bareUrlRe = RegExp(r'^https?://[^\s<>()]+');

/// Phân tích đậm `**x**`, nghiêng `*x*` / `_x_`, mã `` `x` `` và liên kết.
List<MarkdownInline> parseMyNoteInline(String text) {
  final out = <MarkdownInline>[];
  final buffer = StringBuffer();

  void flush() {
    if (buffer.isEmpty) return;
    out.add(MarkdownText(buffer.toString()));
    buffer.clear();
  }

  var i = 0;
  while (i < text.length) {
    final rest = text.substring(i);
    final ch = text[i];
    if (ch == '\\' && i + 1 < text.length && '*_`[]\\'.contains(text[i + 1])) {
      buffer.write(text[i + 1]);
      i += 2;
      continue;
    }
    if (ch == '`') {
      final end = text.indexOf('`', i + 1);
      if (end > i + 1) {
        flush();
        out.add(MarkdownCode(text.substring(i + 1, end)));
        i = end + 1;
        continue;
      }
    }
    if (ch == '[') {
      final match = _linkRe.firstMatch(rest);
      if (match != null) {
        flush();
        out.add(MarkdownLink(match.group(1)!, match.group(2)!));
        i += match.end;
        continue;
      }
    }
    if (ch == 'h') {
      final match = _bareUrlRe.firstMatch(rest);
      if (match != null &&
          (i == 0 || text[i - 1] == ' ' || text[i - 1] == '\n')) {
        flush();
        final url = match.group(0)!.replaceFirst(RegExp(r'[.,;:!?]+$'), '');
        out.add(MarkdownLink(url, url));
        i += url.length;
        continue;
      }
    }
    if (rest.startsWith('**')) {
      final end = text.indexOf('**', i + 2);
      if (end > i + 2) {
        flush();
        out.addAll(
          _styled(parseMyNoteInline(text.substring(i + 2, end)), bold: true),
        );
        i = end + 2;
        continue;
      }
    }
    if (ch == '*' || ch == '_') {
      final end = text.indexOf(ch, i + 1);
      final boundaryOk = ch == '*' || i == 0 || !_isWordChar(text[i - 1]);
      if (end > i + 1 && boundaryOk && text[i + 1] != ' ') {
        flush();
        out.addAll(
          _styled(parseMyNoteInline(text.substring(i + 1, end)), italic: true),
        );
        i = end + 1;
        continue;
      }
    }
    buffer.write(ch);
    i++;
  }
  flush();
  return out;
}

bool _isWordChar(String ch) =>
    RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(ch);

Iterable<MarkdownInline> _styled(
  List<MarkdownInline> inlines, {
  bool bold = false,
  bool italic = false,
}) {
  return inlines.map((inline) {
    if (inline is MarkdownText) {
      return MarkdownText(
        inline.text,
        bold: inline.bold || bold,
        italic: inline.italic || italic,
      );
    }
    return inline;
  });
}

/// Chữ thuần của [source] (bỏ cú pháp markdown), dùng cho xem trước.
String myNoteMarkdownToPlainText(String source) {
  final buffer = StringBuffer();
  for (final block in parseMyNoteMarkdown(source)) {
    String join(List<MarkdownInline> inlines) => inlines
        .map(
          (inline) => switch (inline) {
            MarkdownText(:final text) => text,
            MarkdownCode(:final text) => text,
            MarkdownLink(:final label) => label,
          },
        )
        .join();
    final line = switch (block) {
      MarkdownHeading(:final inlines) => join(inlines),
      MarkdownParagraph(:final inlines) => join(inlines),
      MarkdownBullet(:final inlines) => join(inlines),
      MarkdownNumbered(:final inlines) => join(inlines),
      MarkdownCheckbox(:final inlines) => join(inlines),
      MarkdownCodeBlock(:final code) => code,
    };
    if (buffer.isNotEmpty) buffer.write(' ');
    buffer.write(line.replaceAll('\n', ' '));
  }
  return buffer.toString();
}

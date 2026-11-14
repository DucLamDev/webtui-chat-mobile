import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/my_notes/domain/markdown/my_note_markdown.dart';
import 'package:webtui_chat/features/my_notes/domain/markdown/my_note_markdown_format.dart';

void main() {
  group('parseMyNoteMarkdown', () {
    test('tiêu đề cấp 1-3, đoạn văn tách bởi dòng trống', () {
      final blocks = parseMyNoteMarkdown('# A\n## B\n### C\n#### D\n\nđoạn');
      expect(blocks[0], isA<MarkdownHeading>().having((b) => b.level, 'l', 1));
      expect(blocks[1], isA<MarkdownHeading>().having((b) => b.level, 'l', 2));
      expect(blocks[2], isA<MarkdownHeading>().having((b) => b.level, 'l', 3));
      // #### không phải tiêu đề được hỗ trợ: giữ nguyên là chữ.
      expect(blocks[3], isA<MarkdownParagraph>());
      expect(blocks[4], isA<MarkdownParagraph>());
    });

    test('danh sách gạch đầu dòng, đánh số, ô tick và thụt lề', () {
      final blocks = parseMyNoteMarkdown(
        '- a\n  - b\n1. c\n2) d\n- [ ] e\n- [x] f\n- [X] g',
      );
      expect(blocks[0], isA<MarkdownBullet>());
      expect((blocks[1] as MarkdownBullet).depth, 1);
      expect((blocks[2] as MarkdownNumbered).number, 1);
      expect((blocks[3] as MarkdownNumbered).number, 2);
      expect((blocks[4] as MarkdownCheckbox).checked, isFalse);
      expect((blocks[5] as MarkdownCheckbox).checked, isTrue);
      expect((blocks[6] as MarkdownCheckbox).checked, isTrue);
    });

    test('khối mã giữ nguyên nội dung, không phân tích cú pháp bên trong', () {
      final blocks = parseMyNoteMarkdown(
        '```dart\n# not heading\n**x**\n```\nsau',
      );
      expect(blocks[0], isA<MarkdownCodeBlock>());
      expect((blocks[0] as MarkdownCodeBlock).code, '# not heading\n**x**');
      expect(blocks[1], isA<MarkdownParagraph>());
    });

    test('khối mã chưa đóng vẫn hiện phần còn lại', () {
      final blocks = parseMyNoteMarkdown('```\na\nb');
      expect((blocks.single as MarkdownCodeBlock).code, 'a\nb');
    });

    test('nội dung rỗng không sinh khối', () {
      expect(parseMyNoteMarkdown(''), isEmpty);
      expect(parseMyNoteMarkdown('\n\n  \n'), isEmpty);
    });

    test('nhiều dòng liền nhau gộp thành một đoạn', () {
      final blocks = parseMyNoteMarkdown('một\nhai');
      expect(blocks, hasLength(1));
    });
  });

  group('parseMyNoteInline', () {
    test('đậm, nghiêng, mã nội dòng', () {
      expect(parseMyNoteInline('a **b** *c* `d`'), [
        const MarkdownText('a '),
        const MarkdownText('b', bold: true),
        const MarkdownText(' '),
        const MarkdownText('c', italic: true),
        const MarkdownText(' '),
        const MarkdownCode('d'),
      ]);
    });

    test('liên kết markdown và địa chỉ trần', () {
      expect(parseMyNoteInline('[xem](https://a.vn/x) rồi https://b.vn/y.'), [
        const MarkdownLink('xem', 'https://a.vn/x'),
        const MarkdownText(' rồi '),
        const MarkdownLink('https://b.vn/y', 'https://b.vn/y'),
        const MarkdownText('.'),
      ]);
    });

    test('không nhận liên kết javascript:', () {
      final inlines = parseMyNoteInline('[x](javascript:alert(1))');
      expect(inlines.whereType<MarkdownLink>(), isEmpty);
    });

    test('dấu không khép kín giữ nguyên là chữ', () {
      expect(parseMyNoteInline('2 * 3 và **dở'), [
        const MarkdownText('2 * 3 và **dở'),
      ]);
    });

    test('gạch dưới trong từ không thành nghiêng', () {
      expect(parseMyNoteInline('snake_case_name'), [
        const MarkdownText('snake_case_name'),
      ]);
    });

    test('liên kết / địa chỉ giữa đoạn được nhận đúng vị trí', () {
      expect(parseMyNoteInline('a **b** [c](https://d.vn) e\nhttps://f.vn'), [
        const MarkdownText('a '),
        const MarkdownText('b', bold: true),
        const MarkdownText(' '),
        const MarkdownLink('c', 'https://d.vn'),
        const MarkdownText(' e\n'),
        const MarkdownLink('https://f.vn', 'https://f.vn'),
      ]);
      // Chữ "http" dính liền chữ trước thì không phải địa chỉ.
      expect(parseMyNoteInline('xhttps://g.vn'), [
        const MarkdownText('xhttps://g.vn'),
      ]);
    });

    test('đoạn dài 50.000 ký tự không dòng trống vẫn giữ đủ nội dung', () {
      // Trước đây cắt chuỗi con ở mỗi ký tự (O(n²)); nay quét một lượt.
      final long = List.filled(1700, 'chữ **đậm** [a](https://x.vn) ').join();
      expect(long.length, greaterThan(50000));
      final inlines = parseMyNoteInline(long);
      expect(inlines.whereType<MarkdownLink>(), hasLength(1700));
      expect(
        inlines.whereType<MarkdownText>().where((text) => text.bold),
        hasLength(1700),
      );
      final pathological = '[' * 20000 + 'ahttp://b' * 2000;
      expect(
        parseMyNoteInline(pathological).whereType<MarkdownText>().single.text,
        pathological,
      );
    });
  });

  test('myNoteMarkdownToPlainText bỏ cú pháp', () {
    expect(
      myNoteMarkdownToPlainText('# Tiêu đề\n- **a**\n- [x] [b](https://c.vn)'),
      'Tiêu đề a b',
    );
  });

  group('applyMyNoteFormat', () {
    test('đậm bọc vùng chọn, vùng rỗng chèn cặp dấu', () {
      var r = applyMyNoteFormat(MyNoteFormat.bold, 'abc def', 4, 7);
      expect(r.text, 'abc **def**');
      expect((r.start, r.end), (6, 9));
      r = applyMyNoteFormat(MyNoteFormat.italic, 'ab', 1, 1);
      expect(r.text, 'a**b');
      expect((r.start, r.end), (2, 2));
    });

    test('mã: một dòng dùng backtick, nhiều dòng dùng khối rào', () {
      expect(applyMyNoteFormat(MyNoteFormat.code, 'x', 0, 1).text, '`x`');
      expect(
        applyMyNoteFormat(MyNoteFormat.code, 'a\nb', 0, 3).text,
        '```\na\nb\n```',
      );
    });

    test('tiêu đề / danh sách: thêm rồi gỡ trên cả các dòng được chọn', () {
      var r = applyMyNoteFormat(MyNoteFormat.bullet, 'a\nb\nc', 0, 3);
      expect(r.text, '- a\n- b\nc');
      r = applyMyNoteFormat(MyNoteFormat.bullet, r.text, r.start, r.end);
      expect(r.text, 'a\nb\nc');
    });

    test('đổi kiểu dòng: ô tick thay gạch đầu dòng, tiêu đề thay thế', () {
      expect(
        applyMyNoteFormat(MyNoteFormat.checklist, '- a', 0, 0).text,
        '- [ ] a',
      );
      expect(applyMyNoteFormat(MyNoteFormat.heading, '# a', 1, 1).text, '## a');
    });

    test('vùng chọn không hợp lệ (-1) thao tác ở cuối văn bản', () {
      expect(
        applyMyNoteFormat(MyNoteFormat.checklist, 'ab', -1, -1).text,
        '- [ ] ab',
      );
    });
  });
}

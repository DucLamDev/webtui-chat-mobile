import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/my_notes/domain/markdown/my_note_line_ops.dart';

/// Dựng MyNoteEdit từ chuỗi có `|` đánh dấu con trỏ (một `|`) hoặc vùng chọn
/// (hai `|`).
MyNoteEdit e(String marked) {
  final first = marked.indexOf('|');
  final second = marked.indexOf('|', first + 1);
  if (second == -1) {
    return MyNoteEdit.collapsed(marked.replaceFirst('|', ''), first);
  }
  final text = marked.replaceAll('|', '');
  return MyNoteEdit(text, selectionStart: first, selectionEnd: second - 1);
}

/// Ngược lại của [e] để so sánh dễ đọc.
String show(MyNoteEdit edit) {
  if (edit.isCollapsed) {
    return edit.text.replaceRange(
      edit.selectionStart,
      edit.selectionStart,
      '|',
    );
  }
  return edit.text
      .replaceRange(edit.selectionEnd, edit.selectionEnd, '|')
      .replaceRange(edit.selectionStart, edit.selectionStart, '|');
}

/// Mô phỏng gõ Enter tại con trỏ.
MyNoteEdit? enter(String marked) {
  final before = e(marked);
  final text = before.text.replaceRange(
    before.selectionStart,
    before.selectionEnd,
    '\n',
  );
  return myNoteHandleNewline(
    before,
    MyNoteEdit.collapsed(text, before.selectionStart + 1),
  );
}

/// Mô phỏng xoá lùi một ký tự tại con trỏ.
MyNoteEdit? backspace(String marked) {
  final before = e(marked);
  final at = before.selectionStart;
  return myNoteHandleBackspace(
    before,
    MyNoteEdit.collapsed(before.text.replaceRange(at - 1, at, ''), at - 1),
  );
}

void main() {
  group('parseMyNoteLine', () {
    test('các kiểu dấu đầu dòng', () {
      expect(parseMyNoteLine('# A').style, MyNoteBlockStyle.title);
      expect(parseMyNoteLine('## A').style, MyNoteBlockStyle.heading);
      expect(parseMyNoteLine('### A').style, MyNoteBlockStyle.subheading);
      expect(parseMyNoteLine('#### A').style, MyNoteBlockStyle.body);
      expect(parseMyNoteLine('#tag').style, MyNoteBlockStyle.body);
      expect(parseMyNoteLine('- a').markerLength, 2);
      expect(parseMyNoteLine('* a').style, MyNoteBlockStyle.bullet);
      expect(parseMyNoteLine('+ a').style, MyNoteBlockStyle.bullet);
      expect(parseMyNoteLine('-a').style, MyNoteBlockStyle.body);
      expect(parseMyNoteLine('> a').style, MyNoteBlockStyle.quote);
      expect(parseMyNoteLine('').style, MyNoteBlockStyle.body);
    });

    test('danh sách số, checklist, thụt lề', () {
      final numbered = parseMyNoteLine('  12. x');
      expect(numbered.style, MyNoteBlockStyle.numbered);
      expect(numbered.number, 12);
      expect(numbered.indent, 2);
      expect(numbered.markerLength, 6);
      final open = parseMyNoteLine('- [ ] việc');
      expect(open.style, MyNoteBlockStyle.checklist);
      expect(open.checked, isFalse);
      expect(open.markerLength, 6);
      expect(parseMyNoteLine('* [X] a').checked, isTrue);
      expect(parseMyNoteLine('    - [x] a').indent, 4);
      // Ô tick rỗng ở cuối dòng (không còn khoảng trắng sau).
      expect(parseMyNoteLine('- [ ]').style, MyNoteBlockStyle.checklist);
    });

    test('parseMyNoteLines nhận khối mã, rào chưa đóng thì mã tới cuối', () {
      final lines = parseMyNoteLines('a\n```\n- x\n```\n- y\n```\nz');
      expect(lines[1].isFence, isTrue);
      expect(lines[2].inCode, isTrue);
      expect(lines[2].info.style, MyNoteBlockStyle.monospace);
      expect(lines[3].isFence, isTrue);
      expect(lines[4].info.style, MyNoteBlockStyle.bullet);
      expect(lines[6].inCode, isTrue);
    });
  });

  group('setMyNoteBlockStyle', () {
    test('áp bullet cho một dòng, con trỏ giữ vị trí trong chữ', () {
      final result = setMyNoteBlockStyle(
        e('Tiêu đề\nab|c'),
        MyNoteBlockStyle.bullet,
      );
      expect(show(result), 'Tiêu đề\n- ab|c');
    });

    test('vùng chọn nhiều dòng, chọn lại thì bỏ về body', () {
      final on = setMyNoteBlockStyle(
        e('T\n|a\nb\nc|'),
        MyNoteBlockStyle.checklist,
      );
      expect(on.text, 'T\n- [ ] a\n- [ ] b\n- [ ] c');
      final off = setMyNoteBlockStyle(on, MyNoteBlockStyle.checklist);
      expect(off.text, 'T\na\nb\nc');
    });

    test('đổi từ kiểu khác sang kiểu mới thay dấu cũ', () {
      expect(
        setMyNoteBlockStyle(e('T\n## a|'), MyNoteBlockStyle.bullet).text,
        'T\n- a',
      );
      expect(
        setMyNoteBlockStyle(e('T\n- [x] a|'), MyNoteBlockStyle.quote).text,
        'T\n> a',
      );
      expect(
        setMyNoteBlockStyle(e('T\n- a|'), MyNoteBlockStyle.body).text,
        'T\na',
      );
      expect(
        setMyNoteBlockStyle(e('T\na|'), MyNoteBlockStyle.subheading).text,
        'T\n### a',
      );
    });

    test('danh sách số tăng dần và tiếp số dòng trên', () {
      expect(
        setMyNoteBlockStyle(e('|a\nb\nc|'), MyNoteBlockStyle.numbered).text,
        '1. a\n2. b\n3. c',
      );
      expect(
        setMyNoteBlockStyle(e('1. a\nb|'), MyNoteBlockStyle.numbered).text,
        '1. a\n2. b',
      );
    });

    test('vùng chọn kết thúc ở đầu dòng thì không tính dòng đó', () {
      final result = setMyNoteBlockStyle(e('|a\n|b'), MyNoteBlockStyle.bullet);
      expect(result.text, '- a\nb');
    });

    test('dòng rỗng / văn bản rỗng', () {
      expect(
        show(setMyNoteBlockStyle(e('|'), MyNoteBlockStyle.checklist)),
        '- [ ] |',
      );
      expect(
        show(setMyNoteBlockStyle(e('T\n|'), MyNoteBlockStyle.bullet)),
        'T\n- |',
      );
    });

    test('monospace bọc rào, bấm lại thì gỡ rào', () {
      final on = setMyNoteBlockStyle(
        e('T\n|- a\nb|\nc'),
        MyNoteBlockStyle.monospace,
      );
      expect(on.text, 'T\n```\na\nb\n```\nc');
      expect(show(on), 'T\n```\n|a\nb|\n```\nc');
      final off = setMyNoteBlockStyle(on, MyNoteBlockStyle.monospace);
      expect(off.text, 'T\na\nb\nc');
    });

    test('đổi kiểu dòng trong khối mã thì gỡ khối trước', () {
      final result = setMyNoteBlockStyle(
        e('```\na|\n```'),
        MyNoteBlockStyle.bullet,
      );
      expect(result.text, '- a');
    });
  });

  group('checklist', () {
    test('toggleMyNoteChecklist bật / tắt', () {
      final on = toggleMyNoteChecklist(e('T\nviệc|'));
      expect(show(on), 'T\n- [ ] việc|');
      expect(toggleMyNoteChecklist(on).text, 'T\nviệc');
    });

    test('toggleMyNoteCheckedAt đổi [ ] ↔ [x], giữ vùng chọn', () {
      final edit = e('T\n- [ ] a\n  - [X] b|');
      final first = toggleMyNoteCheckedAt(edit, 2);
      expect(first.text, 'T\n- [x] a\n  - [X] b');
      expect(first.selectionStart, edit.selectionStart);
      final second = toggleMyNoteCheckedAt(first, 10);
      expect(second.text, 'T\n- [x] a\n  - [ ] b');
    });

    test(
      'toggleMyNoteCheckedAt bỏ qua dòng không phải checklist / sai vị trí',
      () {
        final edit = e('- a\n- [ ] b|');
        expect(toggleMyNoteCheckedAt(edit, 0), edit);
        expect(toggleMyNoteCheckedAt(edit, 5), edit);
        expect(toggleMyNoteCheckedAt(edit, 99), edit);
      },
    );
  });

  group('toggleMyNoteInlineStyle', () {
    test('vùng chọn rỗng chèn cặp dấu, bấm lại gỡ', () {
      final on = toggleMyNoteInlineStyle(e('a |'), MyNoteInlineStyle.bold);
      expect(show(on), 'a **|**');
      expect(show(toggleMyNoteInlineStyle(on, MyNoteInlineStyle.bold)), 'a |');
    });

    test('bọc vùng chọn và gỡ khi đã có', () {
      final on = toggleMyNoteInlineStyle(
        e('x |chữ| y'),
        MyNoteInlineStyle.strikethrough,
      );
      expect(show(on), 'x ~~|chữ|~~ y');
      final off = toggleMyNoteInlineStyle(on, MyNoteInlineStyle.strikethrough);
      expect(show(off), 'x |chữ| y');
    });

    test('con trỏ trong đoạn đã định dạng thì gỡ dấu', () {
      final off = toggleMyNoteInlineStyle(
        e('a *ng|hiêng* b'),
        MyNoteInlineStyle.italic,
      );
      expect(show(off), 'a ng|hiêng b');
    });

    test('bọc mã nội dòng, bỏ khoảng trắng hai đầu vùng chọn', () {
      final on = toggleMyNoteInlineStyle(
        e('a| code |b'),
        MyNoteInlineStyle.code,
      );
      expect(on.text, 'a `code` b');
    });

    test('nhiều dòng: bọc từng dòng, bỏ qua dấu đầu dòng', () {
      final on = toggleMyNoteInlineStyle(
        e('|- a\n- b|'),
        MyNoteInlineStyle.bold,
      );
      expect(on.text, '- **a**\n- **b**');
      final off = toggleMyNoteInlineStyle(
        MyNoteEdit(on.text, selectionStart: 0, selectionEnd: on.text.length),
        MyNoteInlineStyle.bold,
      );
      expect(off.text, '- a\n- b');
    });

    test('myNoteInlineStylesAt', () {
      const text = 'a **đậm *cả nghiêng*** ~~g~~ `m`';
      expect(myNoteInlineStylesAt(text, 0), isEmpty);
      expect(myNoteInlineStylesAt(text, 5), {MyNoteInlineStyle.bold});
      expect(myNoteInlineStylesAt(text, 12), {
        MyNoteInlineStyle.bold,
        MyNoteInlineStyle.italic,
      });
      expect(myNoteInlineStylesAt(text, 26), {MyNoteInlineStyle.strikethrough});
      expect(myNoteInlineStylesAt(text, 31), {MyNoteInlineStyle.code});
    });

    test('parseMyNoteInlineSpans không phân tích trong mã nội dòng', () {
      final spans = parseMyNoteInlineSpans('`**a**` và snake_case_name');
      expect(spans.map((s) => s.style), [MyNoteInlineStyle.code]);
    });
  });

  group('myNoteBlockStyleAt', () {
    test('dòng đầu không dấu là title, khối mã là monospace', () {
      const text = 'Tiêu đề\n## H\n- a\n```\nx\n```';
      expect(myNoteBlockStyleAt(text, 0), MyNoteBlockStyle.title);
      expect(myNoteBlockStyleAt(text, 10), MyNoteBlockStyle.heading);
      expect(myNoteBlockStyleAt(text, 14), MyNoteBlockStyle.bullet);
      expect(myNoteBlockStyleAt(text, 22), MyNoteBlockStyle.monospace);
      expect(myNoteBlockStyleAt('', 0), MyNoteBlockStyle.title);
    });
  });

  group('myNoteHandleNewline', () {
    test('checklist / bullet / quote tạo dòng mới cùng dấu', () {
      expect(show(enter('T\n- [x] a|')!), 'T\n- [x] a\n- [ ] |');
      expect(show(enter('T\n  - a|')!), 'T\n  - a\n  - |');
      expect(show(enter('T\n* a|')!), 'T\n* a\n* |');
      expect(show(enter('T\n> a|')!), 'T\n> a\n> |');
    });

    test('Enter giữa dòng tách chữ sang dòng mới có dấu', () {
      expect(show(enter('T\n- ab|cd')!), 'T\n- ab\n- |cd');
    });

    test('danh sách số tăng và đánh lại số phía sau', () {
      expect(show(enter('1. a|')!), '1. a\n2. |');
      expect(
        show(enter('1. a|\n2. b\n  - con\n3. c\nx')!),
        '1. a\n2. |\n3. b\n  - con\n4. c\nx',
      );
      expect(show(enter('9) a|')!), '9) a\n10) |');
    });

    test('dòng danh sách rỗng: bỏ dấu, không thêm dòng', () {
      expect(show(enter('T\n- [ ] a\n- [ ] |')!), 'T\n- [ ] a\n|');
      expect(show(enter('- |')!), '|');
      expect(show(enter('T\n> |')!), 'T\n|');
    });

    test(
      'không can thiệp: body, tiêu đề, trong khối mã, con trỏ trước dấu',
      () {
        expect(enter('abc|'), isNull);
        expect(enter('## H|'), isNull);
        expect(enter('```\n- a|\n```'), isNull);
        expect(enter('T\n|- a'), isNull);
        expect(enter('|'), isNull);
      },
    );

    test('after không phải đúng một "\\n" thì trả null', () {
      final before = e('- a|');
      expect(
        myNoteHandleNewline(before, MyNoteEdit.collapsed('- ab', 4)),
        isNull,
      );
    });
  });

  group('myNoteHandleBackspace', () {
    test('xoá lùi ngay sau dấu thì bỏ cả dấu', () {
      expect(show(backspace('T\n- [ ] |việc')!), 'T\n|việc');
      expect(show(backspace('T\n  - |a')!), 'T\n|a');
      expect(show(backspace('T\n## |H')!), 'T\n|H');
      expect(show(backspace('# |Tiêu đề')!), '|Tiêu đề');
      expect(show(backspace('T\n> |q')!), 'T\n|q');
      expect(show(backspace('T\n3. |x')!), 'T\n|x');
    });

    test('không can thiệp ở chỗ khác', () {
      expect(backspace('T\n- a|'), isNull);
      expect(backspace('T\n|- a'), isNull);
      expect(backspace('ab|'), isNull);
      expect(backspace('```\n- |a\n```'), isNull);
    });
  });

  group('myNoteHiddenLineMarkers', () {
    test('trả vị trí dấu, bỏ qua khối mã', () {
      expect(myNoteHiddenLineMarkers('# T\n- a\nb\n```\n- c\n```\n1. d'), [
        const MyNoteTextRange(0, 2),
        const MyNoteTextRange(4, 6),
        const MyNoteTextRange(22, 25),
      ]);
      expect(myNoteHiddenLineMarkers(''), isEmpty);
    });
  });

  group('extractMyNoteInlineTags', () {
    test('tag tiếng Việt, chữ hoa → thường, bỏ trùng giữ thứ tự', () {
      expect(
        extractMyNoteInlineTags('#Việc-gấp đi chợ #nhà_cửa\n#việc-GẤP #A1'),
        ['việc-gấp', 'nhà_cửa', 'a1'],
      );
    });

    test('không tính tag trong khối mã, mã nội dòng, URL, giữa chữ', () {
      expect(
        extractMyNoteInlineTags(
          '```\n#trongma\n```\n`#noidong` https://a.vn/#frag a#b # đề #ok',
        ),
        ['ok'],
      );
    });

    test('bỏ tag dài hơn 40 ký tự, tối đa 20 tag', () {
      final long = 'a' * 41;
      final exact = 'b' * 40;
      expect(extractMyNoteInlineTags('#$long #$exact'), [exact]);
      final many = List.generate(25, (i) => '#t$i').join(' ');
      final tags = extractMyNoteInlineTags(many);
      expect(tags, hasLength(20));
      expect(tags.first, 't0');
      expect(tags.last, 't19');
    });

    test('văn bản rỗng / không có tag', () {
      expect(extractMyNoteInlineTags(''), isEmpty);
      expect(extractMyNoteInlineTags('# Tiêu đề'), isEmpty);
    });
  });
}

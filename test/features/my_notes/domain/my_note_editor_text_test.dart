import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/my_notes/domain/entities/my_note.dart';
import 'package:webtui_chat/features/my_notes/domain/my_note_editor_text.dart';

void main() {
  group('tách / ghép văn bản ô soạn (dòng đầu là tiêu đề)', () {
    test('dòng đầu là tiêu đề, phần sau là nội dung; ghép lại như cũ', () {
      final parts = splitMyNoteEditorText(
        'Họp tuần\n- [ ] Chốt lịch\n\nGhi thêm',
      );
      expect(parts.title, 'Họp tuần');
      expect(parts.body, '- [ ] Chốt lịch\n\nGhi thêm');
      expect(
        joinMyNoteEditorText(parts.title, parts.body),
        'Họp tuần\n- [ ] Chốt lịch\n\nGhi thêm',
      );
    });

    test('chỉ một dòng: chỉ có tiêu đề', () {
      final parts = splitMyNoteEditorText('Mua sữa');
      expect(parts.title, 'Mua sữa');
      expect(parts.body, '');
      expect(joinMyNoteEditorText('Mua sữa', ''), 'Mua sữa');
    });

    test('bỏ dấu # tiêu đề và dòng trống ở đầu', () {
      expect(splitMyNoteEditorText('# Kế hoạch\nnội dung').title, 'Kế hoạch');
      final parts = splitMyNoteEditorText('\n\n  Kế hoạch  \nnội dung');
      expect(parts.title, 'Kế hoạch');
      expect(parts.body, 'nội dung');
    });

    test('rỗng hoặc chỉ khoảng trắng: không có gì để lưu', () {
      final parts = splitMyNoteEditorText(' \n\n ');
      expect(parts.title, '');
      expect(parts.body, '');
    });

    test(
      'dòng đầu dài quá giới hạn tiêu đề: giữ cả văn bản trong nội dung',
      () {
        final longLine = 'a' * (MyNoteLimits.titleMaxLength + 1);
        final parts = splitMyNoteEditorText('$longLine\nphần sau');
        expect(parts.title, '');
        expect(parts.body, '$longLine\nphần sau');
        // Đúng bằng giới hạn thì vẫn là tiêu đề.
        final exact = 'b' * MyNoteLimits.titleMaxLength;
        expect(splitMyNoteEditorText(exact).title, exact);
      },
    );

    test('ghi chú cũ chưa có tiêu đề: ghép chỉ còn nội dung', () {
      expect(
        joinMyNoteEditorText('', 'Dòng một\nDòng hai'),
        'Dòng một\nDòng hai',
      );
      expect(joinMyNoteEditorText('  ', 'x'), 'x');
    });
  });

  group('tag', () {
    test('chuẩn hoá như máy chủ: bỏ #, gộp khoảng trắng, chữ thường', () {
      expect(normalizeMyNoteTag('  #Việc   Gấp '), 'việc gấp');
      expect(normalizeMyNoteTag('##Nhà'), 'nhà');
      expect(normalizeMyNoteTag('   '), '');
    });

    test('tag đặt từ trước nhưng không có trong chữ thì giữ riêng', () {
      expect(
        myNoteTagsOutsideText(const [
          'account ide',
          'việc',
        ], 'Ghi chú\nNội dung #việc'),
        ['account ide'],
      );
    });

    test(
      'gộp tag: bỏ trùng, bỏ tag rỗng / quá dài / có dấu phẩy, tối đa 20',
      () {
        final tooLong = 'x' * (MyNoteLimits.tagMaxLength + 1);
        expect(
          mergeMyNoteTags(['Nhà', 'việc', tooLong, 'a,b', ''], ['nhà', 'mới']),
          ['nhà', 'việc', 'mới'],
        );
        final many = [for (var i = 0; i < 30; i++) 't$i'];
        expect(
          mergeMyNoteTags(many, const []),
          hasLength(MyNoteLimits.tagsMax),
        );
      },
    );

    test('tag lưu cùng ghi chú = tag riêng + tag gõ trong chữ', () {
      expect(
        myNoteEditorTags('Họp\nchốt #Việc-gấp và #việc-gấp', const ['nhà']),
        ['nhà', 'việc-gấp'],
      );
    });
  });
}

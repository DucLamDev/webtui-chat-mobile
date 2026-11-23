import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/ide_mobile/application/ide_files_service.dart';
import 'package:webtui_chat/features/ide_mobile/application/ide_highlighter.dart';
import 'package:webtui_chat/features/ide_mobile/domain/ide_file_models.dart';
import 'package:webtui_chat/features/ide_mobile/presentation/widgets/files/ide_code_view.dart';
import 'package:webtui_chat/features/ide_mobile/presentation/widgets/files/ide_files_ui.dart';

const _style = TextStyle(color: Colors.white, fontSize: 13);

String _bigDart() => List.generate(
  1200,
  (i) => 'final int value$i = $i; // chú thích số $i\n',
).join();

void main() {
  test('đoạn phẳng ghép lại đúng bằng mã; có lớp keyword', () {
    const code = 'void main() {\n  print("xin chào");\n}\n';
    final segs = ideHighlightSegments(code, 'dart')!;
    expect(segs.map((s) => s.$1).join(), code);
    expect(
      segs.any((s) => s.$2.contains('keyword') || s.$2.contains('built_in')),
      isTrue,
    );
    final span = IdeHighlighter.spanFromSegments(
      segs,
      style: _style,
      dark: true,
    );
    expect(span.toPlainText(), code);
  });

  test('ngôn ngữ lạ hoặc rỗng -> null (chữ thường)', () {
    expect(ideHighlightSegments('abc', 'khong-co'), isNull);
    expect(ideHighlightSegments('', 'dart'), isNull);
    expect(ideHighlightSegments('abc', ''), isNull);
  });

  test('tô ở isolate nền ra đúng chữ', () async {
    final code = _bigDart();
    final segs = await ideHighlightSegmentsAsync(code, 'dart');
    expect(segs, isNotNull);
    expect(segs!.map((s) => s.$1).join(), code);
  });

  testWidgets('tệp lớn: lúc đầu chữ thường, sau đó có màu; chữ không đổi', (
    tester,
  ) async {
    final code = _bigDart();
    expect(code.length, greaterThan(ideHighlightSyncMaxChars));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IdeCodeView(text: code, language: 'dart'),
        ),
      ),
    );
    SelectableText sel() =>
        tester.widget<SelectableText>(find.byType(SelectableText));
    // Chưa tô: một đoạn chữ thường, không con.
    expect(sel().textSpan!.children, isNull);
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(seconds: 2));
    });
    await tester.pump();
    final span = sel().textSpan!;
    expect(span.children, isNotEmpty);
    expect(span.toPlainText(), code);
  });

  testWidgets('tệp nhỏ: tô ngay, build lại không tô lại (cùng đối tượng)', (
    tester,
  ) async {
    const code = 'int a = 1;\n';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IdeCodeView(text: code, language: 'dart'),
        ),
      ),
    );
    final first = tester.widget<SelectableText>(find.byType(SelectableText));
    final a = first.textSpan!;
    expect(a.children, isNotEmpty);
    // Dựng lại cùng dữ liệu: dùng đúng kết quả đã nhớ.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IdeCodeView(text: code, language: 'dart'),
        ),
      ),
    );
    final b = tester.widget<SelectableText>(find.byType(SelectableText));
    expect(identical(a.children, b.textSpan!.children), isTrue);
  });

  test('trần grep: quá 2000 dòng khớp thì cắt và báo', () {
    final hits = [
      for (var i = 0; i < ideGrepMaxHits + 50; i++)
        IdeGrepHit(path: '/a', line: i + 1, text: 'x'),
    ];
    final r = ideCapGrep(IdeSearchResult(hits));
    expect(r.items, hasLength(ideGrepMaxHits));
    expect(r.truncated, isTrue);
    final small = ideCapGrep(IdeSearchResult(hits.take(5).toList()));
    expect(small.items, hasLength(5));
    expect(small.truncated, isFalse);
  });

  test('trần diff: theo số dòng và theo ký tự', () {
    final (none, c0) = ideClipDiff('  \n');
    expect(none, isEmpty);
    expect(c0, isFalse);
    final (ok, c1) = ideClipDiff('+a\n-b\n');
    expect(ok, hasLength(3));
    expect(c1, isFalse);
    final (lines, c2) = ideClipDiff(
      List.generate(ideDiffMaxLines + 10, (i) => '+$i').join('\n'),
    );
    expect(lines, hasLength(ideDiffMaxLines));
    expect(c2, isTrue);
    final (chars, c3) = ideClipDiff('${'+' * 1000}\n' * 1500);
    expect(c3, isTrue);
    expect(chars.join('\n').length, lessThanOrEqualTo(ideDiffMaxChars));
  });

  test('biểu tượng: .txt / .log / .csv là tài liệu chữ, .dart vẫn là mã', () {
    IconData icon(String n) => ideEntryIcon(
      IdeFileEntry(type: IdeEntryType.file, name: n, path: '/a/$n'),
    );
    expect(icon('ghi-chu.txt'), Icons.notes_rounded);
    expect(icon('app.LOG'), Icons.notes_rounded);
    expect(icon('so-lieu.csv'), Icons.notes_rounded);
    expect(icon('main.dart'), Icons.code_rounded);
    expect(icon('anh.png'), Icons.image_outlined);
  });
}

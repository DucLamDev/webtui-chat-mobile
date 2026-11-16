import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/design_system/tokens/webtui_colors.dart';
import 'package:webtui_chat/features/my_notes/domain/markdown/my_note_line_ops.dart';
import 'package:webtui_chat/features/my_notes/presentation/widgets/my_note_rich_text_controller.dart';

const _checkboxKey = ValueKey('my-note-checkbox');

Future<void> _pump(WidgetTester tester, MyNoteRichTextController controller) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: TextField(
          controller: controller,
          maxLines: null,
          inputFormatters: const [MyNoteListInputFormatter()],
        ),
      ),
    ),
  );
}

TextSpan _build(WidgetTester tester, MyNoteRichTextController controller) {
  return controller.buildTextSpan(
    context: tester.element(find.byType(TextField)),
    style: const TextStyle(),
    withComposing: true,
  );
}

/// Các TextSpan lá (có chữ) theo thứ tự.
List<TextSpan> _leaves(TextSpan root) {
  final result = <TextSpan>[];
  root.visitChildren((span) {
    if (span is TextSpan && span.text != null && span.text!.isNotEmpty) {
      result.add(span);
    }
    return true;
  });
  return result;
}

bool _hidden(TextSpan span) =>
    (span.style?.fontSize ?? 17) < 0.1 && span.style?.color?.a == 0;

/// Gõ một lần qua bộ gõ (đi qua input formatter như bàn phím thật).
Future<void> _type(
  WidgetTester tester,
  MyNoteRichTextController controller,
  String text,
  int cursor,
) async {
  tester.testTextInput.updateEditingValue(
    TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: cursor),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('dòng đầu luôn là tiêu đề cỡ 28, dấu # ẩn', (tester) async {
    final controller = MyNoteRichTextController(text: 'Đi chợ\nthân');
    await _pump(tester, controller);
    final leaves = _leaves(_build(tester, controller));
    final title = leaves.firstWhere((s) => s.text!.contains('Đi chợ'));
    expect(title.style!.fontSize, 28);
    expect(title.style!.fontWeight, FontWeight.w700);
    final body = leaves.firstWhere((s) => s.text!.contains('thân'));
    expect(body.style!.fontSize, 17);

    controller.text = '# Đi chợ';
    final marked = _leaves(_build(tester, controller));
    expect(_hidden(marked.firstWhere((s) => s.text == '# ')), isTrue);
  });

  testWidgets('checklist: dấu không hiện chữ, có ô tick, độ dài khớp', (
    tester,
  ) async {
    const text = 'T\n- [ ] việc\n- a\n> q\n1. số';
    final controller = MyNoteRichTextController(text: text);
    await _pump(tester, controller);
    expect(find.byKey(_checkboxKey), findsOneWidget);
    final root = _build(tester, controller);
    // Mỗi ký tự văn bản ứng đúng một ký tự hiển thị.
    expect(root.toPlainText().length, text.length);
    final leaves = _leaves(root);
    expect(_hidden(leaves.firstWhere((s) => s.text == ' [ ] ')), isTrue);
    expect(leaves.any((s) => s.text!.contains('[') && !_hidden(s)), isFalse);
    // Số thứ tự vẫn hiện.
    expect(_hidden(leaves.firstWhere((s) => s.text == '1.')), isFalse);
  });

  testWidgets('bấm ô tick đổi [ ] → [x] và gọi onChecklistToggled', (
    tester,
  ) async {
    final controller = MyNoteRichTextController(text: 'T\n- [ ] việc');
    var toggled = 0;
    controller.onChecklistToggled = () => toggled++;
    await _pump(tester, controller);
    await tester.tap(find.byKey(_checkboxKey));
    await tester.pump();
    expect(controller.text, 'T\n- [x] việc');
    expect(toggled, 1);
    // Dòng đã tick: chữ màu mờ.
    final leaves = _leaves(_build(tester, controller));
    expect(
      leaves.firstWhere((s) => s.text!.contains('việc')).style!.color,
      WebTuiColors.textMuted,
    );
    await tester.tap(find.byKey(_checkboxKey));
    await tester.pump();
    expect(controller.text, 'T\n- [ ] việc');
    expect(toggled, 2);
  });

  testWidgets('readOnly: bấm ô tick không đổi gì', (tester) async {
    final controller = MyNoteRichTextController(text: 'T\n- [ ] việc')
      ..readOnly = true;
    var toggled = 0;
    controller.onChecklistToggled = () => toggled++;
    await _pump(tester, controller);
    await tester.tap(find.byKey(_checkboxKey));
    await tester.pump();
    expect(controller.text, 'T\n- [ ] việc');
    expect(toggled, 0);
  });

  testWidgets('Enter trên checklist tạo dòng "- [ ] " mới', (tester) async {
    const text = 'T\n- [x] a';
    final controller = MyNoteRichTextController(text: text);
    await _pump(tester, controller);
    await tester.showKeyboard(find.byType(TextField));
    controller.selection = const TextSelection.collapsed(offset: text.length);
    await tester.pump();
    await _type(tester, controller, '$text\n', text.length + 1);
    expect(controller.text, 'T\n- [x] a\n- [ ] ');
    expect(controller.selection.baseOffset, controller.text.length);
  });

  testWidgets('Enter trên dòng checklist rỗng thì bỏ dấu', (tester) async {
    const text = 'T\n- [ ] a\n- [ ] ';
    final controller = MyNoteRichTextController(text: text);
    await _pump(tester, controller);
    await tester.showKeyboard(find.byType(TextField));
    controller.selection = const TextSelection.collapsed(offset: text.length);
    await tester.pump();
    await _type(tester, controller, '$text\n', text.length + 1);
    expect(controller.text, 'T\n- [ ] a\n');
    expect(controller.selection.baseOffset, controller.text.length);
  });

  testWidgets('xoá lùi ngay sau dấu thì bỏ dấu, giữ chữ', (tester) async {
    const text = 'T\n- việc';
    final controller = MyNoteRichTextController(text: text);
    await _pump(tester, controller);
    await tester.showKeyboard(find.byType(TextField));
    controller.selection = const TextSelection.collapsed(offset: 4);
    await tester.pump();
    await _type(tester, controller, 'T\n-việc', 3);
    expect(controller.text, 'T\nviệc');
    expect(controller.selection.baseOffset, 2);
  });

  test('con trỏ đặt giữa / đầu dấu ẩn bị dời ra sau dấu', () {
    final controller = MyNoteRichTextController(text: 'T\n- [ ] a\nb');
    controller.selection = const TextSelection.collapsed(offset: 4);
    expect(controller.selection.baseOffset, 8);
    controller.selection = const TextSelection.collapsed(offset: 2);
    expect(controller.selection.baseOffset, 8);
    // Lùi trái từ ngay sau dấu: nhảy về cuối dòng trên, không bị kẹt.
    controller.selection = const TextSelection.collapsed(offset: 7);
    expect(controller.selection.baseOffset, 1);
    // Vùng chọn không rỗng: giữ nguyên.
    controller.selection = const TextSelection(baseOffset: 3, extentOffset: 9);
    expect(controller.selection.baseOffset, 3);
  });

  test('applyEdit / edit đi một vòng', () {
    final controller = MyNoteRichTextController(text: 'abc');
    var notified = 0;
    controller.addListener(() => notified++);
    controller.selection = const TextSelection(baseOffset: 1, extentOffset: 2);
    notified = 0;
    final edit = controller.edit;
    expect(edit.selectionStart, 1);
    expect(edit.selectionEnd, 2);
    controller.applyEdit(const MyNoteEdit.collapsed('xyz', 3));
    expect(notified, 1);
    expect(controller.text, 'xyz');
    expect(controller.selection.baseOffset, 3);
  });

  testWidgets('inline **a**: dấu ẩn khi con trỏ ngoài, hiện mờ khi chạm', (
    tester,
  ) async {
    final controller = MyNoteRichTextController(text: 'T\nx **a** y');
    await _pump(tester, controller);
    controller.selection = const TextSelection.collapsed(offset: 0);
    var marks = _leaves(
      _build(tester, controller),
    ).where((s) => s.text == '**').toList();
    expect(marks, hasLength(2));
    expect(marks.every(_hidden), isTrue);
    final bold = _leaves(
      _build(tester, controller),
    ).firstWhere((s) => s.text == 'a');
    expect(bold.style!.fontWeight, FontWeight.w700);

    controller.selection = const TextSelection.collapsed(offset: 7);
    marks = _leaves(
      _build(tester, controller),
    ).where((s) => s.text == '**').toList();
    expect(marks.any(_hidden), isFalse);
    expect(marks.first.style!.color, WebTuiColors.textMuted);
  });

  testWidgets('#tag và URL tô màu chính, gạch dưới vùng đang gõ dở', (
    tester,
  ) async {
    final controller = MyNoteRichTextController(
      text: 'T\n#việc https://a.vn đang',
    );
    await _pump(tester, controller);
    controller.value = controller.value.copyWith(
      composing: const TextRange(start: 21, end: 25),
    );
    final leaves = _leaves(_build(tester, controller));
    expect(
      leaves.firstWhere((s) => s.text == '#việc').style!.color,
      WebTuiColors.primary,
    );
    final url = leaves.firstWhere((s) => s.text == 'https://a.vn');
    expect(url.style!.decoration, TextDecoration.underline);
    expect(
      leaves.firstWhere((s) => s.text == 'đang').style!.decoration,
      TextDecoration.underline,
    );
  });
}

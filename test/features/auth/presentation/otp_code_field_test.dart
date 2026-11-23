import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/design_system/theme/webtui_theme.dart';
import 'package:webtui_chat/features/auth/presentation/widgets/otp_code_field.dart';

const _fieldKey = Key('otp');

final class _Harness {
  final controller = TextEditingController();
  final focusNode = FocusNode();
  final changes = <String>[];
  final completed = <String>[];

  void dispose() {
    controller.dispose();
    focusNode.dispose();
  }
}

Future<_Harness> _pump(WidgetTester tester, {bool hasError = false}) async {
  final harness = _Harness();
  addTearDown(harness.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: WebTuiTheme.light(),
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: OtpCodeField(
            fieldKey: _fieldKey,
            controller: harness.controller,
            focusNode: harness.focusNode,
            hasError: hasError,
            onChanged: harness.changes.add,
            onCompleted: harness.completed.add,
          ),
        ),
      ),
    ),
  );
  return harness;
}

void main() {
  testWidgets('dán mã có dấu cách thì điền đủ 6 ô và tự gửi một lần', (
    tester,
  ) async {
    final harness = await _pump(tester);

    await tester.enterText(find.byKey(_fieldKey), '123 456');
    await tester.pump();

    expect(harness.controller.text, '123456');
    for (final digit in ['1', '2', '3', '4', '5', '6']) {
      expect(find.text(digit), findsOneWidget);
    }
    expect(harness.completed, ['123456']);

    // Giá trị không đổi (gõ thêm bị chặn ở 6 số) thì không gửi lại.
    await tester.enterText(find.byKey(_fieldKey), '1234567');
    await tester.pump();
    expect(harness.completed, ['123456']);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('gõ từng số chỉ gửi khi vừa đủ 6 số', (tester) async {
    final harness = await _pump(tester);
    for (final value in ['1', '12', '123', '1234', '12345']) {
      await tester.enterText(find.byKey(_fieldKey), value);
      await tester.pump();
    }
    expect(harness.completed, isEmpty);
    await tester.enterText(find.byKey(_fieldKey), '123456');
    await tester.pump();
    expect(harness.completed, ['123456']);
    expect(harness.changes.last, '123456');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('màn hình xoá ô sau khi sai mã thì lần dán sau vẫn tự gửi', (
    tester,
  ) async {
    final harness = await _pump(tester);
    await tester.enterText(find.byKey(_fieldKey), '111111');
    await tester.pump();
    expect(harness.completed, ['111111']);

    harness.controller.clear();
    await tester.pump();
    expect(find.text('1'), findsNothing);

    await tester.enterText(find.byKey(_fieldKey), '222-222');
    await tester.pump();
    expect(harness.completed, ['111111', '222222']);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('chỉ nhận chữ số, có nhãn cho trình đọc màn hình và gợi ý '
      'tự điền mã một lần', (tester) async {
    final semantics = tester.ensureSemantics();
    final harness = await _pump(tester);

    await tester.enterText(find.byKey(_fieldKey), 'ab');
    await tester.pump();
    expect(harness.controller.text, isEmpty);

    expect(find.bySemanticsLabel('Mã xác thực 6 số'), findsOneWidget);
    final field = tester.widget<TextField>(find.byKey(_fieldKey));
    expect(field.autofillHints, contains(AutofillHints.oneTimeCode));
    expect(field.keyboardType, TextInputType.number);
    expect(field.maxLength, 6);
    semantics.dispose();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('ô vừa khít màn 360 điểm, không tràn', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _pump(tester, hasError: true);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}

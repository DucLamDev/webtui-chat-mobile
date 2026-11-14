import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/design_system/components/webtui_components.dart';
import 'package:webtui_chat/design_system/theme/webtui_theme.dart';
import 'package:webtui_chat/design_system/tokens/webtui_colors.dart';

void main() {
  Future<BuildContext> pumpHost(WidgetTester tester) async {
    late BuildContext captured;
    await tester.pumpWidget(
      MaterialApp(
        theme: WebTuiTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) {
              captured = context;
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );
    return captured;
  }

  testWidgets('hỏi xác nhận: nút chính trả true, Huỷ / chạm ngoài trả false', (
    tester,
  ) async {
    final context = await pumpHost(tester);
    bool? result;

    Future<void> open() async {
      showWebTuiConfirmDialog(
        context,
        title: 'Xoá thư mục?',
        message: 'Ghi chú bên trong chuyển ra ngoài.',
        confirmLabel: 'Xoá',
        destructive: true,
      ).then((value) => result = value);
      await tester.pumpAndSettle();
    }

    await open();
    expect(find.text('Xoá thư mục?'), findsOneWidget);
    final confirm = tester.widget<FilledButton>(
      find.descendant(
        of: find.byKey(const Key('webtui_dialog_confirm')),
        matching: find.byType(FilledButton),
        matchRoot: true,
      ),
    );
    expect(confirm.style?.backgroundColor?.resolve({}), WebTuiColors.danger);
    await tester.tap(find.byKey(const Key('webtui_dialog_confirm')));
    await tester.pumpAndSettle();
    expect(result, isTrue);

    await open();
    await tester.tap(find.byKey(const Key('webtui_dialog_cancel')));
    await tester.pumpAndSettle();
    expect(result, isFalse);

    await open();
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });

  testWidgets(
    'nhập chữ: rỗng thì không bấm được, trả chữ đã cắt khoảng trắng',
    (tester) async {
      final context = await pumpHost(tester);
      String? result = 'chưa trả';
      showWebTuiTextInputDialog(
        context,
        title: 'Thư mục mới',
        label: 'Tên thư mục',
        confirmLabel: 'Tạo',
        maxLength: 80,
        validator: (value) => value == 'trùng' ? 'Đã có thư mục này' : null,
      ).then((value) => result = value);
      await tester.pumpAndSettle();

      FilledButton confirmButton() => tester.widget<FilledButton>(
        find.descendant(
          of: find.byKey(const Key('webtui_dialog_confirm')),
          matching: find.byType(FilledButton),
          matchRoot: true,
        ),
      );
      expect(confirmButton().onPressed, isNull);

      await tester.enterText(find.byType(TextField), 'trùng');
      await tester.pump();
      expect(find.text('Đã có thư mục này'), findsOneWidget);
      expect(confirmButton().onPressed, isNull);

      await tester.enterText(find.byType(TextField), '  Dự án A  ');
      await tester.pump();
      expect(confirmButton().onPressed, isNotNull);
      await tester.tap(find.byKey(const Key('webtui_dialog_confirm')));
      await tester.pumpAndSettle();
      expect(result, 'Dự án A');
    },
  );

  testWidgets('3 nút trở lên xếp dọc, nút chính lên đầu', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: WebTuiTheme.light(),
        home: Scaffold(
          body: WebTuiDialog(
            title: 'Chọn',
            actions: [
              WebTuiDialogAction(label: 'Huỷ', onPressed: () {}),
              WebTuiDialogAction(label: 'Phụ', onPressed: () {}),
              WebTuiDialogAction(
                label: 'Chính',
                primary: true,
                onPressed: () {},
              ),
            ],
          ),
        ),
      ),
    );
    final chinh = tester.getTopLeft(find.text('Chính'));
    final huy = tester.getTopLeft(find.text('Huỷ'));
    expect(chinh.dy, lessThan(huy.dy));
  });

  testWidgets('dòng thao tác bảng trượt cao ≥ 60 và gọi onTap', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: WebTuiTheme.light(),
        home: Scaffold(
          body: WebTuiSheetActionTile(
            icon: Icons.play_arrow,
            title: 'Xem video',
            subtitle: 'Phát ngay',
            onTap: () => tapped++,
          ),
        ),
      ),
    );
    expect(
      tester.getSize(find.byType(WebTuiSheetActionTile)).height,
      greaterThanOrEqualTo(60),
    );
    await tester.tap(find.text('Xem video'));
    expect(tapped, 1);
  });

  test('chủ đề: hộp thoại và bảng trượt nền trắng, không phủ màu', () {
    final theme = WebTuiTheme.light();
    expect(theme.dialogTheme.backgroundColor, WebTuiColors.surface);
    expect(theme.dialogTheme.surfaceTintColor, Colors.transparent);
    expect(theme.bottomSheetTheme.backgroundColor, WebTuiColors.surface);
    expect(theme.colorScheme.secondaryContainer, WebTuiColors.primarySoft);
  });
}

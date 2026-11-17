import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/design_system/icons/webtui_icons.dart';
import 'package:webtui_chat/features/settings/presentation/screens/app_settings_screen.dart';

void main() {
  Future<String?> Function() openSheet(
    WidgetTester tester, {
    required List<String?> results,
  }) {
    return () async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  results.add(
                    await showSettingsChoiceSheet<String>(
                      context: context,
                      title: 'Ngôn ngữ',
                      selected: 'vi',
                      options: const [('vi', 'Tiếng Việt'), ('en', 'English')],
                    ),
                  );
                },
                child: const Text('Mở'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Mở'));
      await tester.pumpAndSettle();
      return null;
    };
  }

  testWidgets('bảng chọn hiện mọi lựa chọn, đánh dấu lựa chọn hiện tại', (
    tester,
  ) async {
    final results = <String?>[];
    await openSheet(tester, results: results)();

    expect(find.text('Ngôn ngữ'), findsOneWidget);
    final vi = find.byKey(const ValueKey('settings-choice-vi'));
    final en = find.byKey(const ValueKey('settings-choice-en'));
    expect(
      find.descendant(of: vi, matching: find.byIcon(WebTuiIcons.check)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: en, matching: find.byIcon(WebTuiIcons.check)),
      findsNothing,
    );
    for (final row in [vi, en]) {
      expect(tester.getSize(row).height, greaterThanOrEqualTo(52));
    }
  });

  testWidgets('bấm một lựa chọn thì đóng bảng và trả giá trị đó', (
    tester,
  ) async {
    final results = <String?>[];
    await openSheet(tester, results: results)();

    await tester.tap(find.byKey(const ValueKey('settings-choice-en')));
    await tester.pumpAndSettle();

    expect(results, ['en']);
    expect(find.byKey(const ValueKey('settings-choice-en')), findsNothing);
  });

  testWidgets('đóng bảng không chọn gì thì trả null', (tester) async {
    final results = <String?>[];
    await openSheet(tester, results: results)();

    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    expect(results, [null]);
  });
}

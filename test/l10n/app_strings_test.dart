import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/l10n/app_strings.dart';

void main() {
  test('delegate chọn bản dịch theo mã ngôn ngữ', () async {
    expect(
      await AppStrings.delegate.load(const Locale('en')),
      isA<AppStringsEn>(),
    );
    expect(
      await AppStrings.delegate.load(const Locale('vi')),
      isA<AppStringsVi>(),
    );
    expect(
      await AppStrings.delegate.load(const Locale('fr')),
      isA<AppStringsVi>(),
    );
  });

  test('tr() trả chữ theo ngôn ngữ đang dùng', () {
    addTearDown(() => AppStrings.current = const AppStringsVi());
    expect(tr('Tin nhắn', 'Messages'), 'Tin nhắn');
    AppStrings.current = const AppStringsEn();
    expect(tr('Tin nhắn', 'Messages'), 'Messages');
  });

  testWidgets('không có delegate trong cây thì dùng tiếng Việt', (
    tester,
  ) async {
    late AppStrings strings;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            strings = context.strings;
            return const SizedBox();
          },
        ),
      ),
    );
    expect(strings, isA<AppStringsVi>());
    expect(strings.logout, 'Đăng xuất');
  });

  test('bản tiếng Anh khác bản tiếng Việt ở chuỗi chính', () {
    const vi = AppStringsVi();
    const en = AppStringsEn();
    expect(en.tabSettings, 'Settings');
    expect(vi.tabSettings, 'Cài đặt');
    expect(en.languageNameEn, 'English');
    expect(vi.languageNameVi, 'Tiếng Việt');
  });
}

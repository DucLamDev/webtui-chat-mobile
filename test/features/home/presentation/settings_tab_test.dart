import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/design_system/components/webtui_avatar.dart';
import 'package:webtui_chat/features/home/presentation/screens/home_shell_screen.dart';
import 'package:webtui_chat/l10n/app_strings.dart';

void main() {
  testWidgets('dòng Workspace bấm được cả khi tài khoản chỉ có 1 workspace', (
    tester,
  ) async {
    var opened = 0;
    await tester.pumpWidget(_host(_tab(onWorkspaceTap: () => opened++)));
    await tester.pump();

    expect(find.text('Workspace'), findsOneWidget);
    expect(find.text('Chuyển workspace'), findsNothing);
    expect(find.byIcon(Icons.swap_horiz_rounded), findsNothing);

    await tester.tap(find.byKey(const Key('settings_workspace_row')));
    expect(opened, 1);
  });

  testWidgets('có từ 2 workspace thì ghi Chuyển workspace', (tester) async {
    var opened = 0;
    await tester.pumpWidget(
      _host(_tab(canSwitchWorkspace: true, onWorkspaceTap: () => opened++)),
    );
    await tester.pump();

    expect(find.text('Chuyển workspace'), findsOneWidget);
    expect(find.byIcon(Icons.swap_horiz_rounded), findsOneWidget);

    await tester.tap(find.byKey(const Key('settings_workspace_row')));
    expect(opened, 1);
  });

  testWidgets('thẻ đầu trang hiện tên người dùng và bấm mở hồ sơ', (
    tester,
  ) async {
    var profileOpened = 0;
    await tester.pumpWidget(
      _host(_tab(userName: 'Lan Anh', onProfileTap: () => profileOpened++)),
    );
    await tester.pump();

    expect(find.text('Lan Anh'), findsOneWidget);
    expect(find.text('Hồ sơ cá nhân'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
    // Chữ cái tên khi chưa có ảnh; không còn nút tròn trong thẻ.
    expect(find.text('LA'), findsOneWidget);
    expect(find.byType(IconButton), findsNothing);

    await tester.tap(find.byKey(const Key('settings_profile_card')));
    expect(profileOpened, 1);
  });

  testWidgets('không còn dòng Tài khoản và dòng Hồ sơ cá nhân trùng', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_tab(userName: 'Lan Anh')));
    await tester.pump();

    expect(find.text('Tài khoản'), findsNothing);
    expect(find.text('Cập nhật tên, ảnh đại diện và trạng thái'), findsNothing);
    // Chỉ còn đúng một chỗ ghi "Hồ sơ cá nhân" (dòng phụ của thẻ đầu).
    expect(find.text('Hồ sơ cá nhân'), findsOneWidget);
    expect(find.text('Đăng xuất'), findsOneWidget);
  });

  testWidgets('chưa có tên thì thẻ đầu ghi chữ thay thế', (tester) async {
    await tester.pumpWidget(_host(_tab(userName: '  ')));
    await tester.pump();

    expect(find.text('Tài khoản của bạn'), findsOneWidget);
  });

  testWidgets('locale en thì tab Cài đặt hiện tiếng Anh', (tester) async {
    await tester.pumpWidget(
      _host(_tab(userName: 'Lan Anh', canSwitchWorkspace: true), locale: 'en'),
    );
    await tester.pump();

    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('Switch workspace'), findsOneWidget);
    expect(find.text('Advanced settings'), findsOneWidget);
    expect(find.text('Log out'), findsOneWidget);
    expect(find.text('Đăng xuất'), findsNothing);
  });
}

Widget _host(Widget child, {void Function(Uri uri)? onLoad, String? locale}) {
  return MaterialApp(
    locale: locale == null ? null : Locale(locale),
    supportedLocales: const [Locale('vi'), Locale('en')],
    localizationsDelegates: locale == null
        ? null
        : const [AppStrings.delegate, DefaultWidgetsLocalizations.delegate],
    home: WebTuiAvatarNetworkScope(
      apiBaseUri: Uri.parse('https://chat.example'),
      cacheKey: 'settings-tab-test',
      loadBytes: (uri, {required maxBytes, required allowPublicRequest}) async {
        onLoad?.call(uri);
        return Uint8List(0);
      },
      child: Scaffold(body: child),
    ),
  );
}

SettingsTab _tab({
  bool canSwitchWorkspace = false,
  String userName = 'Người dùng',
  VoidCallback? onWorkspaceTap,
  VoidCallback? onProfileTap,
}) {
  return SettingsTab(
    workspaceName: 'Webtui Chat',
    userName: userName,
    canSwitchWorkspace: canSwitchWorkspace,
    onWorkspaceTap: onWorkspaceTap ?? () {},
    notificationEnabled: true,
    compactMode: false,
    soundLevel: 0.6,
    textScalePreview: 0.4,
    onProfileTap: onProfileTap ?? () {},
    onAdvancedTap: () {},
    onLogoutTap: () {},
    onNotificationChanged: (_) {},
    onCompactChanged: (_) {},
    onSoundChanged: (_) {},
    onTextScaleChanged: (_) {},
  );
}

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/design_system/components/webtui_components.dart';
import 'package:webtui_chat/design_system/icons/webtui_icons.dart';
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
    // Tên workspace là giá trị bên phải của dòng.
    expect(
      find.descendant(
        of: find.byKey(const Key('settings_workspace_row')),
        matching: find.text('Webtui Chat'),
      ),
      findsOneWidget,
    );

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
    expect(find.text('Webtui Chat'), findsOneWidget);

    await tester.tap(find.byKey(const Key('settings_workspace_row')));
    expect(opened, 1);
  });

  testWidgets('đầu trang có tiêu đề lớn Cài đặt và nút Sửa hồ sơ', (
    tester,
  ) async {
    var profileOpened = 0;
    await tester.pumpWidget(_host(_tab(onProfileTap: () => profileOpened++)));
    await tester.pump();

    expect(
      find.descendant(
        of: find.byType(WebTuiLargeTitleBar),
        matching: find.text('Cài đặt'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Sửa hồ sơ'));
    expect(profileOpened, 1);
  });

  testWidgets('đầu hồ sơ: ảnh 92, tên, email; bấm cả khối mở hồ sơ', (
    tester,
  ) async {
    var profileOpened = 0;
    await tester.pumpWidget(
      _host(
        _tab(
          userName: 'Lan Anh',
          userEmail: 'lan.anh@example.com',
          onProfileTap: () => profileOpened++,
        ),
      ),
    );
    await tester.pump();

    final card = find.byKey(const Key('settings_profile_card'));
    expect(
      find.descendant(of: card, matching: find.text('Lan Anh')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.text('lan.anh@example.com')),
      findsOneWidget,
    );
    // Có email thì không ghi "Hồ sơ cá nhân".
    expect(find.text('Hồ sơ cá nhân'), findsNothing);
    final avatar = tester.widget<WebTuiAvatar>(
      find.descendant(of: card, matching: find.byType(WebTuiAvatar)),
    );
    expect(avatar.size, 92);
    // Chữ cái tên khi chưa có ảnh; không còn nút tròn trong khối.
    expect(find.text('LA'), findsOneWidget);
    expect(
      find.descendant(of: card, matching: find.byType(IconButton)),
      findsNothing,
    );

    await tester.tap(find.text('lan.anh@example.com'));
    expect(profileOpened, 1);
    await tester.tap(card);
    expect(profileOpened, 2);
  });

  testWidgets('chưa có email thì dòng phụ ghi Hồ sơ cá nhân', (tester) async {
    await tester.pumpWidget(_host(_tab(userName: 'Lan Anh', userEmail: ' ')));
    await tester.pump();

    expect(find.text('Hồ sơ cá nhân'), findsOneWidget);
  });

  testWidgets('dòng Thiết lập nâng cao mở màn thiết lập', (tester) async {
    var advancedOpened = 0;
    await tester.pumpWidget(_host(_tab(onAdvancedTap: () => advancedOpened++)));
    await tester.pump();

    await tester.tap(find.text('Thiết lập nâng cao'));
    expect(advancedOpened, 1);
  });

  testWidgets('bấm cả dòng Danh sách gọn thì đổi công tắc', (tester) async {
    await tester.pumpWidget(_host(const _CompactHost()));
    await tester.pump();

    expect(find.text('Danh sách dày'), findsNothing);
    expect(find.textContaining('reference'), findsNothing);
    WebTuiToggle toggle() => tester.widget<WebTuiToggle>(
      find.byKey(const Key('settings_compact_toggle')),
    );
    expect(toggle().value, isFalse);

    await tester.tap(find.text('Danh sách gọn'));
    await tester.pumpAndSettle();
    expect(toggle().value, isTrue);

    // Bấm thẳng công tắc vẫn đổi được.
    await tester.tap(find.byKey(const Key('settings_compact_toggle')));
    await tester.pumpAndSettle();
    expect(toggle().value, isFalse);
  });

  testWidgets('bấm cả dòng Thông báo thì đổi giá trị', (tester) async {
    final values = <bool>[];
    await tester.pumpWidget(_host(_tab(onNotificationChanged: values.add)));
    await tester.pump();

    await tester.tap(find.text('Thông báo'));
    expect(values, [false]);
  });

  testWidgets('âm lượng và cỡ chữ là thanh kéo có nhãn', (tester) async {
    await tester.pumpWidget(_host(_tab()));
    await tester.pump();

    expect(find.text('Âm lượng'), findsOneWidget);
    expect(find.text('Cỡ chữ'), findsOneWidget);
    expect(find.byType(Slider), findsNWidgets(2));
  });

  testWidgets('dòng QR chỉ hiện khi máy chủ bật', (tester) async {
    var qrOpened = 0;
    await tester.pumpWidget(_host(_tab()));
    await tester.pump();
    expect(find.byKey(const Key('settings_qr_login_row')), findsNothing);

    await tester.pumpWidget(_host(_tab(onQrLoginTap: () => qrOpened++)));
    await tester.pump();
    await tester.tap(find.byKey(const Key('settings_qr_login_row')));
    expect(qrOpened, 1);
  });

  testWidgets('Đăng xuất màu đỏ, không mũi tên, bấm gọi đăng xuất', (
    tester,
  ) async {
    var loggedOut = 0;
    await tester.pumpWidget(_host(_tab(onLogoutTap: () => loggedOut++)));
    await tester.pump();

    final row = find.byKey(const Key('settings_logout_row'));
    expect(tester.widget<WebTuiSettingRow>(row).destructive, isTrue);
    expect(
      find.descendant(of: row, matching: find.byIcon(WebTuiIcons.forward)),
      findsNothing,
    );
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.tap(row);
    expect(loggedOut, 1);
  });

  testWidgets('không còn dòng Tài khoản và dòng Hồ sơ cá nhân trùng', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_tab(userName: 'Lan Anh')));
    await tester.pump();

    expect(find.text('Tài khoản'), findsNothing);
    expect(find.text('Cập nhật tên, ảnh đại diện và trạng thái'), findsNothing);
    // Chỉ còn đúng một chỗ ghi "Hồ sơ cá nhân" (dòng phụ của đầu hồ sơ).
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

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Edit profile'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('Switch workspace'), findsOneWidget);
    expect(find.text('Advanced settings'), findsOneWidget);
    expect(find.text('Compact list'), findsOneWidget);
    expect(find.text('Volume'), findsOneWidget);
    expect(find.text('Text size'), findsOneWidget);
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
  String? userEmail,
  bool compactMode = false,
  VoidCallback? onWorkspaceTap,
  VoidCallback? onProfileTap,
  VoidCallback? onAdvancedTap,
  VoidCallback? onLogoutTap,
  VoidCallback? onQrLoginTap,
  ValueChanged<bool>? onNotificationChanged,
  ValueChanged<bool>? onCompactChanged,
}) {
  return SettingsTab(
    workspaceName: 'Webtui Chat',
    userName: userName,
    userEmail: userEmail,
    canSwitchWorkspace: canSwitchWorkspace,
    onWorkspaceTap: onWorkspaceTap ?? () {},
    onQrLoginTap: onQrLoginTap,
    notificationEnabled: true,
    compactMode: compactMode,
    soundLevel: 0.6,
    textScalePreview: 0.4,
    onProfileTap: onProfileTap ?? () {},
    onAdvancedTap: onAdvancedTap ?? () {},
    onLogoutTap: onLogoutTap ?? () {},
    onNotificationChanged: onNotificationChanged ?? (_) {},
    onCompactChanged: onCompactChanged ?? (_) {},
    onSoundChanged: (_) {},
    onTextScaleChanged: (_) {},
  );
}

/// Giữ trạng thái Danh sách gọn như màn chính để thấy công tắc đổi thật.
class _CompactHost extends StatefulWidget {
  const _CompactHost();

  @override
  State<_CompactHost> createState() => _CompactHostState();
}

class _CompactHostState extends State<_CompactHost> {
  bool _compact = false;

  @override
  Widget build(BuildContext context) {
    return _tab(
      compactMode: _compact,
      onCompactChanged: (value) => setState(() => _compact = value),
    );
  }
}

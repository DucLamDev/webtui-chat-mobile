import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/design_system/components/webtui_avatar.dart';
import 'package:webtui_chat/features/home/presentation/screens/home_shell_screen.dart';

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

  testWidgets('thẻ đầu trang hiện logo tổ chức thay cho chữ viết tắt', (
    tester,
  ) async {
    final requested = <Uri>[];
    await tester.pumpWidget(
      _host(
        _tab(organizationLogoUrl: '/branding/logo.png'),
        onLoad: requested.add,
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('settings_workspace_logo')), findsOneWidget);
    expect(requested, [Uri.parse('https://chat.example/branding/logo.png')]);
    expect(find.text('WC'), findsNothing);
  });

  testWidgets('máy chủ không có logo thì hiện chữ viết tắt như cũ', (
    tester,
  ) async {
    final requested = <Uri>[];
    await tester.pumpWidget(
      _host(_tab(organizationLogoUrl: '  '), onLoad: requested.add),
    );
    await tester.pump();

    expect(find.byKey(const Key('settings_workspace_logo')), findsNothing);
    expect(find.text('WC'), findsOneWidget);
    expect(requested, isEmpty);
  });
}

Widget _host(Widget child, {void Function(Uri uri)? onLoad}) {
  return MaterialApp(
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
  String? organizationLogoUrl,
  VoidCallback? onWorkspaceTap,
}) {
  return SettingsTab(
    workspaceName: 'Webtui Chat',
    organizationLogoUrl: organizationLogoUrl,
    canSwitchWorkspace: canSwitchWorkspace,
    onWorkspaceTap: onWorkspaceTap ?? () {},
    notificationEnabled: true,
    compactMode: false,
    soundLevel: 0.6,
    textScalePreview: 0.4,
    onProfileTap: () {},
    onAdvancedTap: () {},
    onPrivacyTap: () {},
    onLogoutTap: () {},
    onNotificationChanged: (_) {},
    onCompactChanged: (_) {},
    onSoundChanged: (_) {},
    onTextScaleChanged: (_) {},
  );
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/app/flavor/app_config.dart';
import 'package:webtui_chat/app/flavor/app_flavor.dart';
import 'package:webtui_chat/app/providers/foundation_providers.dart';
import 'package:webtui_chat/core/network/self_hosted_server_discovery.dart';
import 'package:webtui_chat/design_system/theme/webtui_theme.dart';
import 'package:webtui_chat/design_system/tokens/webtui_colors.dart';
import 'package:webtui_chat/features/settings/domain/entities/app_settings.dart';
import 'package:webtui_chat/features/settings/domain/repositories/app_settings_repository.dart';
import 'package:webtui_chat/features/settings/presentation/screens/app_settings_screen.dart';

void main() {
  tearDown(() => WebTuiColors.apply(Brightness.light));

  Future<void> pumpScreen(WidgetTester tester, {required bool dark}) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    WebTuiColors.apply(dark ? Brightness.dark : Brightness.light);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(
            AppConfig(
              flavor: AppFlavor.dev,
              apiBaseUri: Uri.parse('http://localhost:8080'),
              wsBaseUri: Uri.parse('ws://localhost:8080/ws'),
            ),
          ),
          appSettingsRepositoryProvider.overrideWithValue(_MemoryRepository()),
          activeServerDiscoveryProvider.overrideWithValue(_discovery()),
        ],
        child: MaterialApp(
          theme: dark ? WebTuiTheme.dark() : WebTuiTheme.light(),
          home: const AppSettingsScreen(),
        ),
      ),
    );
    // Kiểm tra phiên bản / quyền thông báo chạy nền lúc mở màn: cho chạy xong
    // để không còn bộ đếm giờ treo khi test kết thúc.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(milliseconds: 10));
  }

  Color? headerColor(WidgetTester tester, String label) =>
      tester.widget<Text>(find.text(label)).style?.color;

  testWidgets('sáng: nhóm là thẻ trắng trên nền xám, tiêu đề nhóm màu xám', (
    tester,
  ) async {
    await pumpScreen(tester, dark: false);
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
      WebTuiColors.groupBackground,
    );
    expect(
      find.byKey(const Key('settings_section_card')),
      findsAtLeastNWidgets(4),
    );
    expect(headerColor(tester, 'Thông báo'), WebTuiColors.textMuted);
    expect(headerColor(tester, 'Thông báo'), isNot(WebTuiColors.primary));
    // Nút cuối dòng là nút viên thuốc, không còn nút chữ xanh.
    expect(find.byType(TextButton), findsNothing);
    expect(
      find.widgetWithText(SettingsActionButton, 'Cho phép'),
      findsOneWidget,
    );
  });

  testWidgets('tối: giữ nền liền, không chia thẻ; tiêu đề nhóm màu xám', (
    tester,
  ) async {
    await pumpScreen(tester, dark: true);
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
      WebTuiColors.page,
    );
    expect(find.byKey(const Key('settings_section_card')), findsNothing);
    expect(headerColor(tester, 'Giao diện'), WebTuiColors.textMuted);
  });

  testWidgets('chưa bật khoá ứng dụng: không có dòng thời gian khoá', (
    tester,
  ) async {
    await pumpScreen(tester, dark: false);
    expect(find.text('Khóa ứng dụng'), findsOneWidget);
    expect(find.textContaining('Tự khóa'), findsNothing);
  });
}

class _MemoryRepository implements AppSettingsRepository {
  AppSettings _settings = const AppSettings();

  @override
  Future<AppSettings> read() async => _settings;

  @override
  Future<void> save(AppSettings settings) async => _settings = settings;
}

SelfHostedServerDiscovery _discovery() => SelfHostedServerDiscovery(
  instanceId: '11111111-1111-4111-8111-111111111111',
  discoveryVersion: '1',
  domain: 'localhost',
  name: 'Company Chat',
  apiBaseUri: Uri.parse('http://localhost:8080'),
  wsBaseUri: Uri.parse('ws://localhost:8080/ws'),
  registrationMode: 'open',
  appVersion: 'test',
  apiContractVersion: 1,
  serverVersion: 'test',
  minimumSupportedMobileVersion: '1.0.0',
  capabilities: const SelfHostedCapabilities(
    moderation: true,
    reporting: true,
    blocking: true,
    accountDeletion: true,
    legalAcceptance: true,
  ),
);

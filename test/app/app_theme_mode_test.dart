import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/app/app.dart';
import 'package:webtui_chat/app/flavor/app_config.dart';
import 'package:webtui_chat/app/flavor/app_flavor.dart';
import 'package:webtui_chat/app/providers/foundation_providers.dart';
import 'package:webtui_chat/core/network/self_hosted_server_discovery.dart';
import 'package:webtui_chat/design_system/tokens/webtui_colors.dart';
import 'package:webtui_chat/features/settings/domain/entities/app_settings.dart';
import 'package:webtui_chat/features/settings/domain/repositories/app_settings_repository.dart';
import 'package:webtui_chat/features/settings/presentation/controllers/app_settings_controller.dart';

void main() {
  tearDown(() => WebTuiColors.apply(Brightness.light));

  testWidgets('chọn Tối rồi Sáng có tác dụng ngay trên toàn app', (
    tester,
  ) async {
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
          activeServerDiscoveryProvider.overrideWithValue(_discovery()),
          appSettingsRepositoryProvider.overrideWithValue(
            _MemorySettingsRepository(),
          ),
        ],
        child: const WebTuiChatApp(),
      ),
    );
    await tester.pump();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(WebTuiChatApp)),
    );
    final controller = container.read(appSettingsControllerProvider.notifier);
    await controller.update(
      const AppSettings(theme: WebTuiThemePreference.dark),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    final context = tester.element(find.byType(Scaffold).first);
    expect(Theme.of(context).brightness, Brightness.dark);
    expect(WebTuiColors.brightness, Brightness.dark);

    await controller.update(
      const AppSettings(theme: WebTuiThemePreference.light),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(
      Theme.of(tester.element(find.byType(Scaffold).first)).brightness,
      Brightness.light,
    );
    expect(WebTuiColors.brightness, Brightness.light);
  });
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

class _MemorySettingsRepository implements AppSettingsRepository {
  AppSettings _settings = const AppSettings();

  @override
  Future<AppSettings> read() async => _settings;

  @override
  Future<void> save(AppSettings settings) async => _settings = settings;
}

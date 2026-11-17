import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/app/app.dart';
import 'package:webtui_chat/app/flavor/app_config.dart';
import 'package:webtui_chat/app/flavor/app_flavor.dart';
import 'package:webtui_chat/app/providers/foundation_providers.dart';
import 'package:webtui_chat/core/network/self_hosted_server_discovery.dart';
import 'package:webtui_chat/core/notifications/call_tone_player.dart';
import 'package:webtui_chat/features/settings/domain/entities/app_settings.dart';
import 'package:webtui_chat/features/settings/domain/repositories/app_settings_repository.dart';
import 'package:webtui_chat/features/settings/presentation/controllers/app_settings_controller.dart';

Widget _app(_MemorySettingsRepository repository) => ProviderScope(
  overrides: [
    appConfigProvider.overrideWithValue(
      AppConfig(
        flavor: AppFlavor.dev,
        apiBaseUri: Uri.parse('http://localhost:8080'),
        wsBaseUri: Uri.parse('ws://localhost:8080/ws'),
      ),
    ),
    activeServerDiscoveryProvider.overrideWithValue(_discovery()),
    appSettingsRepositoryProvider.overrideWithValue(repository),
  ],
  child: const WebTuiChatApp(),
);

double _scaledTen(WidgetTester tester) => MediaQuery.textScalerOf(
  tester.element(find.byType(Scaffold).first),
).scale(10);

void main() {
  tearDown(() => CallTonePlayer.volume = CallTonePlayer.defaultVolume);

  testWidgets('Cỡ chữ / Âm lượng ở Cài đặt có tác dụng ngay trên toàn app', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_MemorySettingsRepository()));
    await tester.pump();
    expect(_scaledTen(tester), closeTo(10, 1e-9));
    expect(CallTonePlayer.volume, appSoundVolumeDefault);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(WebTuiChatApp)),
    );
    await container
        .read(appSettingsControllerProvider.notifier)
        .update(const AppSettings(textScale: 1.3, soundVolume: 0.3));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    // Chữ cả app phóng 130%; chuông cuộc gọi dùng âm lượng mới.
    expect(_scaledTen(tester), closeTo(13, 1e-9));
    expect(CallTonePlayer.volume, 0.3);
  });

  testWidgets('mở lại app: cỡ chữ và âm lượng đã lưu được áp dụng', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        _MemorySettingsRepository(
          const AppSettings(textScale: 1.15, soundVolume: 0),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(_scaledTen(tester), closeTo(11.5, 1e-9));
    expect(CallTonePlayer.volume, 0);
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
  _MemorySettingsRepository([this._settings = const AppSettings()]);

  AppSettings _settings;

  @override
  Future<AppSettings> read() async => _settings;

  @override
  Future<void> save(AppSettings settings) async => _settings = settings;
}

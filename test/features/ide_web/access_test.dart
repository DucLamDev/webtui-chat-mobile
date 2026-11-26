import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/app/flavor/app_config.dart';
import 'package:webtui_chat/app/flavor/app_flavor.dart';
import 'package:webtui_chat/app/providers/foundation_providers.dart';
import 'package:webtui_chat/core/network/self_hosted_server_discovery.dart';
import 'package:webtui_chat/features/conversations/presentation/widgets/workspace_modules.dart';
import 'package:webtui_chat/features/ide_mobile/application/ide_access.dart';
import 'package:webtui_chat/features/ide_web/application/ide_web_access.dart';
import 'package:webtui_chat/features/ide_web/application/ide_web_providers.dart';

/// TC1: ô "VPSTTT IDE" chỉ hiện ở máy chủ nội bộ đã bật tích hợp.
SelfHostedServerDiscovery _discovery({
  String domain = 'chat.vpsttt.com',
  String kind = 'vpsttt_internal',
  Object? ideWeb = true,
  Object? ideWebUrl = 'https://ide.chat.vpsttt.com',
  Object? ideWebAuthUrl = 'https://ide.vpsttt.net',
  bool ide = false,
}) => SelfHostedServerDiscovery.fromApiResponse(
  requestedServer: Uri.parse('https://$domain'),
  mobileVersion: '1.2.0',
  payload: {
    'data': {
      'version': '1',
      'instance_id': '11111111-1111-4111-8111-111111111111',
      'domain': domain,
      'zone': {'status': 'active', 'name': 'Test', 'kind': kind},
      'runtime': {
        'api_base_url': 'https://$domain',
        'ws_base_url': 'wss://$domain/ws',
        'api_contract_version': 1,
        'server_version': '1.0.0',
        'app_version': '1.0.0',
        'minimum_supported_mobile_version': '1.0.0',
        'ide_web_base_url': ?ideWebUrl,
        'ide_web_auth_base_url': ?ideWebAuthUrl,
      },
      'deployment': {'status': 'ready'},
      'capabilities': {
        'self_hosted': true,
        'chat': true,
        'moderation': true,
        'reporting': true,
        'blocking': true,
        'account_deletion': true,
        'legal_acceptance': true,
        'ide': ide,
        'ide_web': ?ideWeb,
      },
    },
  },
);

Set<String> _enabledTiles(SelfHostedServerDiscovery? discovery) {
  final container = ProviderContainer(
    overrides: [
      appConfigProvider.overrideWithValue(AppConfig.fromFlavor(AppFlavor.dev)),
      activeServerDiscoveryProvider.overrideWithValue(discovery),
    ],
  );
  addTearDown(container.dispose);
  return {
    for (final module in container.read(workspaceModulesProvider))
      if (module.enabled) module.id,
  };
}

void main() {
  // Nền mặc định của flutter_test là Android.
  test('bật đủ điều kiện: hiện ô mới, ẩn ô IDE cũ, giữ nguyên ô khác', () {
    expect(_enabledTiles(_discovery(ide: true)), {'ide_web'});
    expect(_enabledTiles(_discovery()), {'ide_web'});
    expect(_enabledTiles(_discovery(ide: true, ideWeb: false)), {'ide'});
    expect(_enabledTiles(null), isEmpty);
  });

  test('thiếu một điều kiện là tắt và ô cũ không đổi hành vi', () {
    for (final discovery in [
      _discovery(kind: 'dedicated'),
      _discovery(
        domain: 'chat.example.com',
        ideWebUrl: 'https://ide.chat.example.com',
      ),
      _discovery(ideWeb: null),
      _discovery(ideWeb: 'true'),
      _discovery(ideWebUrl: null),
      _discovery(ideWebAuthUrl: null),
      _discovery(ideWebAuthUrl: 'https://ide.chat.vpsttt.com'),
    ]) {
      expect(discovery.ideWebEnabled, isFalse);
      expect(_enabledTiles(discovery), isNot(contains('ide_web')));
    }
  });

  test('địa chỉ nhúng sai dạng coi như tắt', () {
    for (final url in const [
      'http://ide.chat.vpsttt.com',
      'https://ide.chat.vpsttt.com/',
      'https://ide.chat.vpsttt.com/x',
      'https://ide.chat.vpsttt.com?x=1',
      'https://ide.chat.vpsttt.com#x',
      'https://ide.chat.vpsttt.com:8443',
      'https://a@ide.chat.vpsttt.com',
      'https://ide.chat.vpsttt.com.evil.example',
      'https://evil.example',
      'https://chat.vpsttt.com',
      'javascript:alert(1)',
      '',
      'ide.chat.vpsttt.com',
    ]) {
      expect(_discovery(ideWebUrl: url).ideWebBaseUri, isNull, reason: url);
    }
    expect(_discovery(ideWebUrl: 42).ideWebBaseUri, isNull);
  });

  test('địa chỉ đăng nhập IDE: đọc chặt, sai / thiếu coi như không có', () {
    for (final url in const [
      'https://ide.vpsttt.net',
      'https://ide.vpsttt.net/',
      'https://IDE.vpsttt.net',
      'https://ide.vpsttt.net:443',
    ]) {
      final discovery = _discovery(ideWebAuthUrl: url);
      expect(
        discovery.ideWebAuthBaseUri,
        Uri.parse('https://ide.vpsttt.net'),
        reason: url,
      );
      expect(discovery.ideWebEnabled, isTrue, reason: url);
    }
    for (final url in const [
      'http://ide.vpsttt.net',
      'https://ide.vpsttt.net/appchat/auth/',
      'https://ide.vpsttt.net/x',
      'https://ide.vpsttt.net?x=1',
      'https://ide.vpsttt.net/?x=1',
      'https://ide.vpsttt.net#x',
      'https://ide.vpsttt.net:8443',
      'https://a@ide.vpsttt.net',
      'https://a:b@ide.vpsttt.net',
      // Trùng host nhúng / tên miền chat (kể cả dấu chấm cuối).
      'https://ide.chat.vpsttt.com',
      'https://IDE.chat.vpsttt.com',
      'https://ide.chat.vpsttt.com.',
      'https://chat.vpsttt.com',
      'https://ide.vpsttt.net.',
      'https://localhost',
      'https://ide_vpsttt.net',
      'javascript:alert(1)',
      'ide.vpsttt.net',
      '',
    ]) {
      final discovery = _discovery(ideWebAuthUrl: url);
      expect(discovery.ideWebAuthBaseUri, isNull, reason: url);
      expect(discovery.ideWebEnabled, isFalse, reason: url);
    }
    expect(_discovery(ideWebAuthUrl: 42).ideWebAuthBaseUri, isNull);
  });

  test('chính sách host có cả địa chỉ đăng nhập; thiếu thì tắt', () {
    ProviderContainer container(SelfHostedServerDiscovery discovery) {
      final value = ProviderContainer(
        overrides: [activeServerDiscoveryProvider.overrideWithValue(discovery)],
      );
      addTearDown(value.dispose);
      return value;
    }

    final policy = container(_discovery()).read(ideWebHostPolicyProvider)!;
    expect(policy.origin, 'https://ide.chat.vpsttt.com');
    expect(policy.authOrigin, 'https://ide.vpsttt.net');
    final off = container(_discovery(ideWebAuthUrl: null));
    expect(off.read(ideWebHostPolicyProvider), isNull);
    expect(off.read(ideWebAuthBaseUriProvider), isNull);
  });

  test(
    'ảnh discovery lưu trên máy giữ nguyên; bản cũ thiếu trường thì tắt',
    () {
      SelfHostedServerDiscovery roundTrip(SelfHostedServerDiscovery value) =>
          SelfHostedServerDiscovery.fromStorageSnapshot(
            encodedSnapshot: value.toStorageSnapshot(),
            mobileVersion: '1.2.0',
          );
      expect(
        roundTrip(_discovery()).ideWebBaseUri,
        Uri.parse('https://ide.chat.vpsttt.com'),
      );
      expect(
        roundTrip(_discovery()).ideWebAuthBaseUri,
        Uri.parse('https://ide.vpsttt.net'),
      );
      expect(roundTrip(_discovery()).ideWebEnabled, isTrue);
      // Ảnh lưu trước bản này: chưa có địa chỉ đăng nhập thì tắt.
      final old = roundTrip(_discovery(ideWebAuthUrl: null));
      expect(old.ideWebBaseUri, isNotNull);
      expect(old.ideWebAuthBaseUri, isNull);
      expect(old.ideWebEnabled, isFalse);
      expect(
        roundTrip(_discovery(ideWeb: null, ideWebUrl: null)).ideWebEnabled,
        isFalse,
      );
    },
  );

  test('chỉ Android / iOS', () {
    for (final platform in TargetPlatform.values) {
      debugDefaultTargetPlatformOverride = platform;
      final container = ProviderContainer(
        overrides: [
          activeServerDiscoveryProvider.overrideWithValue(_discovery()),
        ],
      );
      expect(
        container.read(ideWebEnabledProvider),
        ideSupportedPlatform(platform),
        reason: '$platform',
      );
      container.dispose();
    }
    debugDefaultTargetPlatformOverride = null;
  });

  test('đường dẫn ô mở đúng màn', () {
    final container = ProviderContainer(
      overrides: [
        activeServerDiscoveryProvider.overrideWithValue(_discovery()),
      ],
    );
    addTearDown(container.dispose);
    final module = container
        .read(workspaceModulesProvider)
        .singleWhere((m) => m.id == 'ide_web');
    expect(module.routeFor('ws'), '/ide-web');
    expect(module.title, 'VPSTTT IDE');
  });
}

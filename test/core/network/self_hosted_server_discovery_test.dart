import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/network/self_hosted_server_discovery.dart';

void main() {
  test('parses a ready self-hosted discovery runtime', () {
    final discovery = SelfHostedServerDiscovery.fromApiResponse(
      payload: _payload(),
      requestedServer: Uri.parse('https://chat.company.example'),
      mobileVersion: '1.2.0',
    );

    expect(discovery.domain, 'chat.company.example');
    expect(discovery.name, 'Company Chat');
    expect(discovery.apiBaseUri, Uri.parse('https://chat.company.example'));
    expect(discovery.wsBaseUri, Uri.parse('wss://chat.company.example/ws'));
    expect(
      discovery.logoUrl,
      'https://chat.company.example/branding/company-logo.png',
    );
    expect(discovery.canRegister, isTrue);
  });

  test('internal VPSTTT modules only on chat.vpsttt.com internal zone', () {
    SelfHostedServerDiscovery parse(String domain, String? kind) {
      return SelfHostedServerDiscovery.fromApiResponse(
        payload: _payload(
          domain: domain,
          apiBaseUrl: 'https://$domain',
          wsBaseUrl: 'wss://$domain/ws',
          zoneKind: kind,
        ),
        requestedServer: Uri.parse('https://$domain'),
        mobileVersion: '1.2.0',
      );
    }

    final internal = parse('chat.vpsttt.com', 'vpsttt_internal');
    expect(internal.zoneKind, 'vpsttt_internal');
    expect(internal.vpstttInternalModules, isTrue);
    expect(internal.automationEnabled, isTrue);

    // Khách tự host bật automation trên server của họ vẫn không có module nội bộ.
    expect(
      parse('chat.company.example', 'dedicated').automationEnabled,
      isFalse,
    );
    expect(
      parse('chat.company.example', 'vpsttt_internal').automationEnabled,
      isFalse,
    );
    // Server cũ không trả kind: mặc định tắt.
    expect(parse('chat.vpsttt.com', null).automationEnabled, isFalse);

    // Snapshot lưu trên máy giữ nguyên zone kind.
    final restored = SelfHostedServerDiscovery.fromStorageSnapshot(
      encodedSnapshot: internal.toStorageSnapshot(),
      mobileVersion: '1.2.0',
    );
    expect(restored.zoneKind, 'vpsttt_internal');
    expect(restored.automationEnabled, isTrue);
  });

  test('rejects a runtime URL on another host', () {
    expect(
      () => SelfHostedServerDiscovery.fromApiResponse(
        payload: _payload(apiBaseUrl: 'https://attacker.example'),
        requestedServer: Uri.parse('https://chat.company.example'),
        mobileVersion: '1.2.0',
      ),
      throwsStateError,
    );
    expect(
      () => SelfHostedServerDiscovery.fromApiResponse(
        payload: _payload(
          domain: 'chat.example',
          apiBaseUrl: 'https://chat.example:8443',
          wsBaseUrl: 'wss://chat.example/ws',
        ),
        requestedServer: Uri.parse('https://chat.example:8443'),
        mobileVersion: '1.0.0',
      ),
      throwsStateError,
    );
  });

  test('rejects runtime URLs on a different port of the same host', () {
    expect(
      () => SelfHostedServerDiscovery.fromApiResponse(
        payload: _payload(
          domain: 'chat.example',
          apiBaseUrl: 'https://chat.example',
          wsBaseUrl: 'wss://chat.example/ws',
        ),
        requestedServer: Uri.parse('https://chat.example:8443'),
        mobileVersion: '1.0.0',
      ),
      throwsStateError,
    );
  });

  test('uses the requested local runtime for development', () {
    final discovery = SelfHostedServerDiscovery.fromApiResponse(
      payload: _payload(
        domain: 'localhost',
        apiBaseUrl: 'https://localhost',
        wsBaseUrl: 'wss://localhost/ws',
      ),
      requestedServer: Uri.parse('http://localhost:8080'),
      mobileVersion: '1.2.0',
    );

    expect(discovery.apiBaseUri, Uri.parse('http://localhost:8080'));
    expect(discovery.wsBaseUri, Uri.parse('ws://localhost:8080/ws'));
  });

  test('rejects a compatible instance when chat is disabled', () {
    expect(
      () => SelfHostedServerDiscovery.fromApiResponse(
        payload: _payload(chat: false),
        requestedServer: Uri.parse('https://chat.company.example'),
        mobileVersion: '1.2.0',
      ),
      throwsStateError,
    );
  });

  test('restores every capability from a validated cold-start snapshot', () {
    final discovery = SelfHostedServerDiscovery.fromApiResponse(
      payload: _payload(files: false, calls: false),
      requestedServer: Uri.parse('https://chat.company.example'),
      mobileVersion: '1.2.0',
    );

    final restored = SelfHostedServerDiscovery.fromStorageSnapshot(
      encodedSnapshot: discovery.toStorageSnapshot(),
      mobileVersion: '1.2.0',
    );

    expect(restored.instanceId, discovery.instanceId);
    expect(restored.instanceScope, discovery.instanceScope);
    expect(restored.capabilities.files, isFalse);
    expect(restored.capabilities.calls, isFalse);
    expect(restored.capabilities.moderation, isTrue);
    expect(restored.capabilities.legalAcceptance, isTrue);
  });

  test('rejects discovery missing a mandatory safety capability', () {
    final payload = _payload();
    final discovery =
        (payload['data']! as Map<String, Object?>)['discovery']!
            as Map<String, Object?>;
    final capabilities = discovery['capabilities']! as Map<String, Object?>;
    capabilities.remove('reporting');

    expect(
      () => SelfHostedServerDiscovery.fromApiResponse(
        payload: payload,
        requestedServer: Uri.parse('https://chat.company.example'),
        mobileVersion: '1.2.0',
      ),
      throwsStateError,
    );
  });

  test('stale snapshot cannot override a stricter live mobile minimum', () {
    final cached = SelfHostedServerDiscovery.fromApiResponse(
      payload: _payload(minimumMobileVersion: '1.0.0'),
      requestedServer: Uri.parse('https://chat.company.example'),
      mobileVersion: '1.2.0',
    );
    expect(
      SelfHostedServerDiscovery.fromStorageSnapshot(
        encodedSnapshot: cached.toStorageSnapshot(),
        mobileVersion: '1.2.0',
      ).instanceId,
      cached.instanceId,
    );

    expect(
      () => SelfHostedServerDiscovery.fromApiResponse(
        payload: _payload(minimumMobileVersion: '2.0.0'),
        requestedServer: Uri.parse('https://chat.company.example'),
        mobileVersion: '1.2.0',
      ),
      throwsStateError,
    );
  });
}

Map<String, Object?> _payload({
  String domain = 'chat.company.example',
  String apiBaseUrl = 'https://chat.company.example',
  String wsBaseUrl = 'wss://chat.company.example/ws',
  bool chat = true,
  bool files = true,
  bool calls = true,
  String minimumMobileVersion = '1.1.0',
  String? zoneKind,
  bool automation = true,
}) {
  return {
    'data': {
      'discovery': {
        'version': '1',
        'instance_id': '11111111-1111-4111-8111-111111111111',
        'domain': domain,
        'zone': {
          'name': 'Company Chat',
          'status': 'active',
          'registration_mode': 'open',
          'kind': ?zoneKind,
        },
        'runtime': {
          'app_name': 'Company Chat',
          'logo_url': '/branding/company-logo.png',
          'app_version': 'self-hosted',
          'server_version': 'self-hosted',
          'api_contract_version': 1,
          'minimum_supported_mobile_version': minimumMobileVersion,
          'api_base_url': apiBaseUrl,
          'ws_base_url': wsBaseUrl,
        },
        'capabilities': {
          'self_hosted': true,
          'chat': chat,
          'files': files,
          'calls': calls,
          'bots': true,
          'automation': automation,
          'moderation': true,
          'reporting': true,
          'blocking': true,
          'account_deletion': true,
          'legal_acceptance': true,
        },
        'deployment': {'status': 'ready'},
      },
    },
  };
}

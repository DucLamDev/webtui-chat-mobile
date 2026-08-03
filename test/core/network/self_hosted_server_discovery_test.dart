import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/network/self_hosted_server_discovery.dart';

void main() {
  test('parses a ready self-hosted discovery runtime', () {
    final discovery = SelfHostedServerDiscovery.fromApiResponse(
      payload: _payload(),
      requestedServer: Uri.parse('https://chat.company.example'),
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

  test('rejects a runtime URL on another host', () {
    expect(
      () => SelfHostedServerDiscovery.fromApiResponse(
        payload: _payload(apiBaseUrl: 'https://attacker.example'),
        requestedServer: Uri.parse('https://chat.company.example'),
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
    );

    expect(discovery.apiBaseUri, Uri.parse('http://localhost:8080'));
    expect(discovery.wsBaseUri, Uri.parse('ws://localhost:8080/ws'));
  });

  test('rejects a compatible instance when chat is disabled', () {
    expect(
      () => SelfHostedServerDiscovery.fromApiResponse(
        payload: _payload(chat: false),
        requestedServer: Uri.parse('https://chat.company.example'),
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
}) {
  return {
    'data': {
      'discovery': {
        'domain': domain,
        'zone': {
          'name': 'Company Chat',
          'status': 'active',
          'registration_mode': 'open',
        },
        'runtime': {
          'app_name': 'Company Chat',
          'logo_url': '/branding/company-logo.png',
          'app_version': '1.0.0',
          'api_base_url': apiBaseUrl,
          'ws_base_url': wsBaseUrl,
        },
        'capabilities': {'self_hosted': true, 'chat': chat},
        'deployment': {'status': 'ready'},
      },
    },
  };
}

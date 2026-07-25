import 'self_hosted_server_uri.dart';

final class SelfHostedServerDiscovery {
  const SelfHostedServerDiscovery({
    required this.domain,
    required this.name,
    required this.apiBaseUri,
    required this.wsBaseUri,
    required this.registrationMode,
    required this.appVersion,
  });

  factory SelfHostedServerDiscovery.fromApiResponse({
    required Object? payload,
    required Uri requestedServer,
  }) {
    final root = _jsonMap(payload);
    final data = _jsonMap(root['data']);
    final discovery = _jsonMap(
      data.isNotEmpty ? data['discovery'] : root['discovery'] ?? root,
    );
    if (discovery.isEmpty) {
      throw StateError('Server không trả discovery WebTUI Chat hợp lệ.');
    }

    final domain = _text(discovery['domain']).toLowerCase();
    final zone = _jsonMap(discovery['zone']);
    final runtime = _jsonMap(discovery['runtime']);
    final capabilities = _jsonMap(discovery['capabilities']);
    final deployment = _jsonMap(discovery['deployment']);

    if (domain != requestedServer.host.toLowerCase()) {
      throw StateError('Domain discovery không khớp với server đã nhập.');
    }
    if (_text(zone['status']).toLowerCase() != 'active') {
      throw StateError('Instance chưa ở trạng thái hoạt động.');
    }
    if (_text(deployment['status']).toLowerCase() != 'ready') {
      throw StateError('Instance đang cài đặt hoặc chưa sẵn sàng.');
    }
    if (capabilities['self_hosted'] != true) {
      throw StateError(
        'Domain này không phải instance WebTUI Chat self-hosted.',
      );
    }

    final isLocal = _isLocalHost(requestedServer.host);
    final apiBaseUri = isLocal
        ? requestedServer
        : _httpRuntimeUri(
            _text(runtime['api_base_url']),
            requestedServer,
            'API',
          );
    final wsBaseUri = isLocal
        ? _defaultWsUri(requestedServer)
        : _wsRuntimeUri(_text(runtime['ws_base_url']), requestedServer);

    final name = _text(zone['name']).isNotEmpty
        ? _text(zone['name'])
        : _text(runtime['app_name']);

    return SelfHostedServerDiscovery(
      domain: domain,
      name: name.isEmpty ? domain : name,
      apiBaseUri: apiBaseUri,
      wsBaseUri: wsBaseUri,
      registrationMode:
          _text(zone['registration_mode']).toLowerCase().isNotEmpty
          ? _text(zone['registration_mode']).toLowerCase()
          : 'closed',
      appVersion: _text(runtime['app_version']),
    );
  }

  final String domain;
  final String name;
  final Uri apiBaseUri;
  final Uri wsBaseUri;
  final String registrationMode;
  final String appVersion;

  bool get canRegister => registrationMode == 'open';
}

Uri parseSelfHostedWebSocketUri(String value) {
  final parsed = Uri.tryParse(value.trim());
  if (parsed == null ||
      parsed.host.isEmpty ||
      parsed.userInfo.isNotEmpty ||
      parsed.query.isNotEmpty ||
      parsed.fragment.isNotEmpty) {
    throw const FormatException('Địa chỉ WebSocket không hợp lệ.');
  }
  final isLocal = _isLocalHost(parsed.host);
  if (parsed.scheme != 'wss' && !(isLocal && parsed.scheme == 'ws')) {
    throw const FormatException('WebSocket public phải sử dụng WSS.');
  }
  return parsed;
}

Uri _httpRuntimeUri(String value, Uri requestedServer, String label) {
  final parsed = parseSelfHostedServerUri(value);
  if (parsed.host.toLowerCase() != requestedServer.host.toLowerCase()) {
    throw StateError('$label URL không cùng domain với instance.');
  }
  return parsed;
}

Uri _wsRuntimeUri(String value, Uri requestedServer) {
  final parsed = parseSelfHostedWebSocketUri(value);
  if (parsed.host.toLowerCase() != requestedServer.host.toLowerCase()) {
    throw StateError('WebSocket URL không cùng domain với instance.');
  }
  return parsed;
}

Uri _defaultWsUri(Uri server) {
  return Uri(
    scheme: server.scheme == 'https' ? 'wss' : 'ws',
    host: server.host,
    port: server.hasPort ? server.port : null,
    path: '/ws',
  );
}

bool _isLocalHost(String host) {
  return host == 'localhost' ||
      host == '127.0.0.1' ||
      host.endsWith('.localhost');
}

Map<String, Object?> _jsonMap(Object? value) {
  if (value is! Map) {
    return const {};
  }
  return value.map((key, item) => MapEntry(key.toString(), item));
}

String _text(Object? value) {
  return value is String ? value.trim() : '';
}

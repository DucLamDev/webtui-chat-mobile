import 'dart:convert';

import '../security/instance_scope.dart';
import 'self_hosted_server_uri.dart';

final class SelfHostedServerDiscovery {
  const SelfHostedServerDiscovery({
    required this.instanceId,
    required this.discoveryVersion,
    required this.domain,
    required this.name,
    required this.apiBaseUri,
    required this.wsBaseUri,
    required this.registrationMode,
    required this.appVersion,
    required this.apiContractVersion,
    required this.serverVersion,
    required this.minimumSupportedMobileVersion,
    required this.capabilities,
    this.logoUrl,
  });

  factory SelfHostedServerDiscovery.fromApiResponse({
    required Object? payload,
    required Uri requestedServer,
    required String mobileVersion,
  }) {
    final root = _jsonMap(payload);
    final data = _jsonMap(root['data']);
    final nestedDataDiscovery = _jsonMap(data['discovery']);
    final rootDiscovery = _jsonMap(root['discovery']);
    final discovery = nestedDataDiscovery.isNotEmpty
        ? nestedDataDiscovery
        : data.isNotEmpty
        ? data
        : rootDiscovery.isNotEmpty
        ? rootDiscovery
        : root;
    if (discovery.isEmpty) {
      throw StateError('Server không trả thông tin discovery hợp lệ.');
    }

    final discoveryVersion = _text(discovery['version']);
    final instanceId = _text(discovery['instance_id']).toLowerCase();
    final domain = _text(discovery['domain']).toLowerCase();
    final zone = _jsonMap(discovery['zone']);
    final runtime = _jsonMap(discovery['runtime']);
    final capabilities = _jsonMap(discovery['capabilities']);
    final deployment = _jsonMap(discovery['deployment']);
    final branding = _jsonMap(discovery['branding']);

    if (discoveryVersion != '1') {
      throw StateError('Unsupported discovery version.');
    }
    try {
      InstanceScope(instanceId: instanceId, serverOrigin: requestedServer);
    } on FormatException {
      throw StateError('Server did not provide a valid instance_id UUID.');
    }

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
        'Domain này không phải một server chat self-hosted tương thích.',
      );
    }
    if (capabilities['chat'] != true) {
      throw StateError('Server này không bật tính năng WebTUI Chat.');
    }
    const requiredSafetyCapabilities = <String>[
      'moderation',
      'reporting',
      'blocking',
      'account_deletion',
      'legal_acceptance',
    ];
    for (final capability in requiredSafetyCapabilities) {
      if (capabilities[capability] != true) {
        throw StateError('Missing required safety capability: $capability.');
      }
    }

    final apiContractVersion = runtime['api_contract_version'];
    if (apiContractVersion is! int || apiContractVersion != 1) {
      throw StateError('Unsupported API contract version.');
    }
    final serverVersion = _text(runtime['server_version']);
    final legacyAppVersion = _text(runtime['app_version']);
    final minimumSupportedMobileVersion = _text(
      runtime['minimum_supported_mobile_version'],
    );
    final parsedMinimumMobileVersion = _SemanticVersion.tryParse(
      minimumSupportedMobileVersion,
    );
    final parsedMobileVersion = _SemanticVersion.tryParse(mobileVersion);
    if (serverVersion.isEmpty ||
        legacyAppVersion.isEmpty ||
        serverVersion != legacyAppVersion ||
        parsedMinimumMobileVersion == null ||
        parsedMobileVersion == null) {
      throw StateError('Server version metadata is invalid.');
    }
    if (parsedMobileVersion.compareTo(parsedMinimumMobileVersion) < 0) {
      throw StateError('This mobile app version is no longer supported.');
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
    final logoUrl = _resolveLogoUrl(
      _text(runtime['logo_url']).isNotEmpty
          ? _text(runtime['logo_url'])
          : _text(zone['logo_url']).isNotEmpty
          ? _text(zone['logo_url'])
          : _text(branding['logo_url']),
      requestedServer,
    );

    return SelfHostedServerDiscovery(
      instanceId: instanceId,
      discoveryVersion: discoveryVersion,
      domain: domain,
      name: name.isEmpty ? domain : name,
      apiBaseUri: apiBaseUri,
      wsBaseUri: wsBaseUri,
      registrationMode:
          _text(zone['registration_mode']).toLowerCase().isNotEmpty
          ? _text(zone['registration_mode']).toLowerCase()
          : 'closed',
      appVersion: legacyAppVersion,
      apiContractVersion: apiContractVersion,
      serverVersion: serverVersion,
      minimumSupportedMobileVersion: minimumSupportedMobileVersion,
      capabilities: SelfHostedCapabilities(
        chat: capabilities['chat'] == true,
        files: capabilities['files'] == true,
        calls: capabilities['calls'] == true,
        bots: capabilities['bots'] == true,
        automation: capabilities['automation'] == true,
        webhooks: capabilities['webhooks'] == true,
        federation: capabilities['federation'] == true,
        sso: capabilities['sso'] == true,
        moderation: capabilities['moderation'] == true,
        reporting: capabilities['reporting'] == true,
        blocking: capabilities['blocking'] == true,
        accountDeletion: capabilities['account_deletion'] == true,
        legalAcceptance: capabilities['legal_acceptance'] == true,
      ),
      logoUrl: logoUrl,
    );
  }

  factory SelfHostedServerDiscovery.fromStorageSnapshot({
    required String encodedSnapshot,
    required String mobileVersion,
  }) {
    final decoded = jsonDecode(encodedSnapshot);
    final snapshot = _jsonMap(decoded);
    if (snapshot['schema'] != 1) {
      throw const FormatException('Discovery snapshot schema is invalid.');
    }
    final requestedServer = parseSelfHostedServerUri(
      _text(snapshot['requested_server']),
    );
    return SelfHostedServerDiscovery.fromApiResponse(
      payload: snapshot['discovery'],
      requestedServer: requestedServer,
      mobileVersion: mobileVersion,
    );
  }

  final String instanceId;
  final String discoveryVersion;
  final String domain;
  final String name;
  final Uri apiBaseUri;
  final Uri wsBaseUri;
  final String registrationMode;
  final String appVersion;
  final int apiContractVersion;
  final String serverVersion;
  final String minimumSupportedMobileVersion;
  final SelfHostedCapabilities capabilities;
  final String? logoUrl;

  bool get canRegister => registrationMode == 'open';

  InstanceScope get instanceScope =>
      InstanceScope(instanceId: instanceId, serverOrigin: apiBaseUri);

  String toStorageSnapshot() {
    return jsonEncode({
      'schema': 1,
      'requested_server': apiBaseUri.toString(),
      'discovery': {
        'version': discoveryVersion,
        'instance_id': instanceId,
        'domain': domain,
        'zone': {
          'status': 'active',
          'name': name,
          'registration_mode': registrationMode,
          'logo_url': logoUrl,
        },
        'runtime': {
          'api_base_url': apiBaseUri.toString(),
          'ws_base_url': wsBaseUri.toString(),
          'app_name': name,
          'logo_url': logoUrl,
          'api_contract_version': apiContractVersion,
          'server_version': serverVersion,
          'app_version': appVersion,
          'minimum_supported_mobile_version': minimumSupportedMobileVersion,
        },
        'deployment': {'status': 'ready'},
        'capabilities': capabilities.toJson(),
      },
    });
  }
}

final class SelfHostedCapabilities {
  const SelfHostedCapabilities({
    this.chat = true,
    this.files = true,
    this.calls = true,
    this.bots = true,
    this.automation = true,
    this.webhooks = true,
    this.federation = false,
    this.sso = false,
    this.moderation = false,
    this.reporting = false,
    this.blocking = false,
    this.accountDeletion = false,
    this.legalAcceptance = false,
  });

  final bool chat;
  final bool files;
  final bool calls;
  final bool bots;
  final bool automation;
  final bool webhooks;
  final bool federation;
  final bool sso;
  final bool moderation;
  final bool reporting;
  final bool blocking;
  final bool accountDeletion;
  final bool legalAcceptance;

  Map<String, bool> toJson() {
    return {
      'self_hosted': true,
      'chat': chat,
      'files': files,
      'calls': calls,
      'bots': bots,
      'automation': automation,
      'webhooks': webhooks,
      'federation': federation,
      'sso': sso,
      'moderation': moderation,
      'reporting': reporting,
      'blocking': blocking,
      'account_deletion': accountDeletion,
      'legal_acceptance': legalAcceptance,
    };
  }
}

final class _SemanticVersion implements Comparable<_SemanticVersion> {
  const _SemanticVersion(this.major, this.minor, this.patch, this.preRelease);

  static final RegExp _pattern = RegExp(
    r'^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)'
    r'(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?'
    r'(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$',
  );

  static _SemanticVersion? tryParse(String value) {
    final match = _pattern.firstMatch(value.trim());
    if (match == null) {
      return null;
    }
    return _SemanticVersion(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
      match.group(4),
    );
  }

  final int major;
  final int minor;
  final int patch;
  final String? preRelease;

  @override
  int compareTo(_SemanticVersion other) {
    for (final comparison in <int>[
      major.compareTo(other.major),
      minor.compareTo(other.minor),
      patch.compareTo(other.patch),
    ]) {
      if (comparison != 0) {
        return comparison;
      }
    }
    if (preRelease == null) {
      return other.preRelease == null ? 0 : 1;
    }
    if (other.preRelease == null) {
      return -1;
    }
    final left = preRelease!.split('.');
    final right = other.preRelease!.split('.');
    final count = left.length < right.length ? left.length : right.length;
    for (var index = 0; index < count; index += 1) {
      final leftNumber = int.tryParse(left[index]);
      final rightNumber = int.tryParse(right[index]);
      final comparison = leftNumber != null && rightNumber != null
          ? leftNumber.compareTo(rightNumber)
          : leftNumber != null
          ? -1
          : rightNumber != null
          ? 1
          : left[index].compareTo(right[index]);
      if (comparison != 0) {
        return comparison;
      }
    }
    return left.length.compareTo(right.length);
  }
}

String? _resolveLogoUrl(String value, Uri requestedServer) {
  if (value.isEmpty) {
    return null;
  }
  final parsed = Uri.tryParse(value);
  if (parsed == null || parsed.userInfo.isNotEmpty) {
    return null;
  }
  final resolved = parsed.hasScheme
      ? parsed
      : requestedServer.resolveUri(parsed);
  final isLocal = _isLocalHost(resolved.host);
  if (resolved.scheme != 'https' && !(isLocal && resolved.scheme == 'http')) {
    return null;
  }
  return resolved.toString();
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
  if (!serverOriginsMatch(parsed, requestedServer)) {
    throw StateError('$label URL không cùng origin với instance.');
  }
  return parsed;
}

Uri _wsRuntimeUri(String value, Uri requestedServer) {
  final parsed = parseSelfHostedWebSocketUri(value);
  final expectedScheme = requestedServer.scheme == 'https' ? 'wss' : 'ws';
  final expectedPort = requestedServer.hasPort
      ? requestedServer.port
      : requestedServer.scheme == 'https'
      ? 443
      : 80;
  final actualPort = parsed.hasPort
      ? parsed.port
      : parsed.scheme == 'wss'
      ? 443
      : 80;
  if (parsed.scheme != expectedScheme ||
      parsed.host.toLowerCase() != requestedServer.host.toLowerCase() ||
      actualPort != expectedPort) {
    throw StateError('WebSocket URL không cùng origin với instance.');
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

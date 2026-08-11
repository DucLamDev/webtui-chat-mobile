import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> arguments) async {
  final platform = switch (arguments) {
    ['--platform=android'] => 'android',
    ['--platform=ios'] => 'ios',
    _ => '',
  };
  if (platform.isEmpty) {
    stderr.writeln(
      'Usage: dart run tool/check_public_release_endpoints.dart '
      '--platform=android|ios',
    );
    exitCode = 64;
    return;
  }

  final environment = Platform.environment;
  final failures = <String>[];
  final releaseMobileVersion = _tagMobileVersion(
    environment['GITHUB_REF_NAME']?.trim() ?? '',
  );
  String required(String name) {
    final value = environment[name]?.trim() ?? '';
    if (value.isEmpty) failures.add('$name is required.');
    return value;
  }

  final apiBaseUrl = required(
    'WEBTUI_API_BASE_URL',
  ).replaceAll(RegExp(r'/+$'), '');
  final appLinkHost = required('WEBTUI_APP_LINK_HOST');
  final termsVersion = required('WEBTUI_TERMS_VERSION');
  final privacyVersion = required('WEBTUI_PRIVACY_VERSION');
  final publicUrls = <String, String>{
    'privacy policy': required('WEBTUI_PRIVACY_POLICY_URL'),
    'Terms': required('WEBTUI_TERMS_URL'),
    'account deletion': required('WEBTUI_ACCOUNT_DELETION_URL'),
    'support': required('WEBTUI_SUPPORT_URL'),
  };
  if (failures.isNotEmpty) {
    _finish(failures);
    return;
  }

  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10)
    ..userAgent = 'WebTUI-Release-Readiness/1.0';
  try {
    await _expectSuccess(
      client,
      '$apiBaseUrl/ready',
      'backend readiness',
      failures,
    );
    final referenceOrigin = Uri.parse(apiBaseUrl);
    final discoveryUri = referenceOrigin.replace(
      path: '/api/v1/discovery',
      queryParameters: {'domain': referenceOrigin.host},
    );
    final discoveryBody = await _expectSuccess(
      client,
      discoveryUri.toString(),
      'reference self-host discovery',
      failures,
      allowRedirects: false,
      requireJsonContentType: true,
    );
    final wellKnownBody = await _expectSuccess(
      client,
      referenceOrigin.resolve('/.well-known/vpsttt-chat').toString(),
      'reference self-host well-known discovery',
      failures,
      allowRedirects: false,
      requireJsonContentType: true,
    );
    final discovery = discoveryBody == null
        ? null
        : _validateSelfHostedDiscovery(
            discoveryBody,
            referenceOrigin: referenceOrigin,
            releaseMobileVersion: releaseMobileVersion,
            label: 'reference discovery',
            failures: failures,
          );
    final wellKnownDiscovery = wellKnownBody == null
        ? null
        : _validateSelfHostedDiscovery(
            wellKnownBody,
            referenceOrigin: referenceOrigin,
            releaseMobileVersion: releaseMobileVersion,
            label: 'well-known discovery',
            failures: failures,
          );
    if (discovery != null && wellKnownDiscovery != null) {
      for (final field in const ['version', 'instance_id', 'domain']) {
        if ('${discovery[field] ?? ''}' !=
            '${wellKnownDiscovery[field] ?? ''}') {
          failures.add(
            'Discovery API and /.well-known/vpsttt-chat disagree on $field.',
          );
        }
      }
    }
    final legalDocumentsBody = await _expectSuccess(
      client,
      '$apiBaseUrl/api/v1/auth/legal-documents',
      'backend legal-document versions',
      failures,
      allowRedirects: false,
      requireJsonContentType: true,
    );
    if (legalDocumentsBody != null) {
      _validateLegalDocumentVersions(
        legalDocumentsBody,
        expectedTermsVersion: termsVersion,
        expectedPrivacyVersion: privacyVersion,
        failures: failures,
      );
    }
    for (final entry in publicUrls.entries) {
      final body = await _expectSuccess(
        client,
        entry.value,
        entry.key,
        failures,
      );
      final expectedVersion = switch (entry.key) {
        'Terms' => termsVersion,
        'privacy policy' => privacyVersion,
        _ => '',
      };
      if (body != null &&
          expectedVersion.isNotEmpty &&
          !body.contains(expectedVersion)) {
        failures.add(
          '${entry.key} does not publish configured version '
          '$expectedVersion: ${entry.value}',
        );
      }
    }

    if (platform == 'android') {
      final fingerprints = required('PLAY_APP_SIGNING_SHA256_FINGERPRINTS')
          .split(RegExp(r'[,;\n]+'))
          .map(_normalizeFingerprint)
          .where((value) => value.isNotEmpty)
          .toSet();
      final body = await _expectSuccess(
        client,
        'https://$appLinkHost/.well-known/assetlinks.json',
        'Android Digital Asset Links',
        failures,
        allowRedirects: false,
        requireJsonContentType: true,
      );
      if (body != null) {
        try {
          final statements = jsonDecode(body);
          if (statements is! List ||
              !statements.any((statement) {
                if (statement is! Map<String, dynamic>) return false;
                final relations = (statement['relation'] as List?)
                    ?.map((value) => '$value')
                    .toSet();
                if (relations == null ||
                    !relations.contains(
                      'delegate_permission/common.handle_all_urls',
                    )) {
                  return false;
                }
                final target = statement['target'];
                if (target is! Map<String, dynamic> ||
                    target['package_name'] != 'com.vpsttt.webtui_chat') {
                  return false;
                }
                final published =
                    (target['sha256_cert_fingerprints'] as List?)
                        ?.map((value) => _normalizeFingerprint('$value'))
                        .toSet() ??
                    const <String>{};
                return fingerprints.isNotEmpty &&
                    fingerprints.every(published.contains);
              })) {
            failures.add(
              'assetlinks.json does not authorize the production package with '
              'every configured Play App Signing certificate.',
            );
          }
        } on FormatException catch (error) {
          failures.add('assetlinks.json is not valid JSON: $error');
        }
      }
    } else {
      final teamId = required('APPLE_TEAM_ID');
      final bundleId = required('APPLE_BUNDLE_ID');
      final body = await _expectSuccess(
        client,
        'https://$appLinkHost/.well-known/apple-app-site-association',
        'Apple universal-link association',
        failures,
        allowRedirects: false,
        requireJsonContentType: true,
      );
      if (body != null) {
        try {
          final association = jsonDecode(body);
          final expectedAppId = '$teamId.$bundleId';
          final associationMap = association is Map<String, dynamic>
              ? association
              : const <String, dynamic>{};
          final applinks = associationMap['applinks'];
          final details = applinks is Map<String, dynamic>
              ? applinks['details']
              : null;
          Map<String, dynamic>? authorizedDetail;
          if (details is List) {
            for (final detail in details) {
              if (detail is! Map<String, dynamic>) continue;
              final appIds = (detail['appIDs'] as List?)
                  ?.map((value) => '$value')
                  .toSet();
              if (detail['appID'] == expectedAppId ||
                  appIds?.contains(expectedAppId) == true) {
                authorizedDetail = detail;
                break;
              }
            }
          }
          if (authorizedDetail == null) {
            failures.add(
              'apple-app-site-association does not authorize $expectedAppId.',
            );
          } else {
            _validateAppleLinkPaths(authorizedDetail, failures);
          }
        } on FormatException catch (error) {
          failures.add('apple-app-site-association is not valid JSON: $error');
        }
      }
    }
  } finally {
    client.close(force: true);
  }

  _finish(failures);
}

Map<String, dynamic>? _validateSelfHostedDiscovery(
  String body, {
  required Uri referenceOrigin,
  required String? releaseMobileVersion,
  required String label,
  required List<String> failures,
}) {
  try {
    final decoded = jsonDecode(body);
    final root = decoded is Map<String, dynamic>
        ? decoded
        : const <String, dynamic>{};
    final data = root['data'] is Map<String, dynamic>
        ? root['data'] as Map<String, dynamic>
        : root;
    final rawDiscovery = data['discovery'] ?? root['discovery'] ?? data;
    if (rawDiscovery is! Map) {
      failures.add('$label does not contain a discovery object.');
      return null;
    }
    final discovery = rawDiscovery.map(
      (key, value) => MapEntry(key.toString(), value),
    );
    final zone = _stringMap(discovery['zone']);
    final runtime = _stringMap(discovery['runtime']);
    final capabilities = _stringMap(discovery['capabilities']);
    final deployment = _stringMap(discovery['deployment']);

    if ('${discovery['version'] ?? ''}' != '1') {
      failures.add('$label must publish discovery version 1.');
    }
    final instanceId = '${discovery['instance_id'] ?? ''}'.trim();
    final uuid = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
    );
    if (!uuid.hasMatch(instanceId)) {
      failures.add('$label instance_id must be an immutable UUID.');
    }
    if ('${zone['id'] ?? ''}'.trim().toLowerCase() !=
        instanceId.toLowerCase()) {
      failures.add('$label instance_id must equal zone.id.');
    }
    if ('${discovery['domain'] ?? ''}'.trim().toLowerCase() !=
        referenceOrigin.host.toLowerCase()) {
      failures.add('$label domain does not match the reference origin.');
    }
    if ('${zone['status'] ?? ''}'.toLowerCase() != 'active' ||
        '${deployment['status'] ?? ''}'.toLowerCase() != 'ready') {
      failures.add('$label zone/deployment is not active and ready.');
    }
    if (runtime['api_contract_version'] != 1) {
      failures.add('$label must publish api_contract_version 1.');
    }
    final minimumMobileVersion =
        '${runtime['minimum_supported_mobile_version'] ?? ''}'.trim();
    if (!RegExp(r'^\d+\.\d+\.\d+$').hasMatch(minimumMobileVersion)) {
      failures.add(
        '$label minimum_supported_mobile_version must be semantic x.y.z.',
      );
    } else if (releaseMobileVersion != null &&
        _compareStableVersions(releaseMobileVersion, minimumMobileVersion) <
            0) {
      failures.add(
        '$label requires mobile $minimumMobileVersion or newer, but the '
        'release tag is mobile-v$releaseMobileVersion.',
      );
    }

    final api = Uri.tryParse('${runtime['api_base_url'] ?? ''}');
    final websocket = Uri.tryParse('${runtime['ws_base_url'] ?? ''}');
    if (api == null ||
        api.scheme != 'https' ||
        api.host.toLowerCase() != referenceOrigin.host.toLowerCase() ||
        api.userInfo.isNotEmpty) {
      failures.add('$label API URL must be HTTPS on the reference host.');
    }
    if (websocket == null ||
        websocket.scheme != 'wss' ||
        websocket.host.toLowerCase() != referenceOrigin.host.toLowerCase() ||
        websocket.userInfo.isNotEmpty) {
      failures.add('$label WebSocket URL must be WSS on the reference host.');
    }

    for (final capability in const [
      'self_hosted',
      'chat',
      'moderation',
      'reporting',
      'blocking',
      'account_deletion',
      'legal_acceptance',
    ]) {
      if (capabilities[capability] != true) {
        failures.add('$label must enable required capability $capability.');
      }
    }
    return discovery;
  } on FormatException catch (error) {
    failures.add('$label is not valid JSON: $error');
    return null;
  }
}

String? _tagMobileVersion(String refName) {
  final match = RegExp(r'^mobile-v(\d+\.\d+\.\d+)$').firstMatch(refName);
  return match?.group(1);
}

int _compareStableVersions(String left, String right) {
  final leftParts = left.split('.').map(int.parse).toList(growable: false);
  final rightParts = right.split('.').map(int.parse).toList(growable: false);
  for (var index = 0; index < 3; index += 1) {
    final comparison = leftParts[index].compareTo(rightParts[index]);
    if (comparison != 0) return comparison;
  }
  return 0;
}

Map<String, dynamic> _stringMap(Object? value) {
  if (value is! Map) return const <String, dynamic>{};
  return value.map((key, item) => MapEntry(key.toString(), item));
}

void _validateAppleLinkPaths(
  Map<String, dynamic> detail,
  List<String> failures,
) {
  final publishedPaths = <String>{};
  final components = detail['components'];
  if (components is List) {
    for (final component in components) {
      if (component is Map<String, dynamic> && component['/'] is String) {
        publishedPaths.add(component['/'] as String);
      }
    }
  }
  final legacyPaths = detail['paths'];
  if (legacyPaths is List) {
    publishedPaths.addAll(legacyPaths.map((value) => '$value'));
  }

  const expectedPaths = {
    '/conversations',
    '/conversations/*',
    '/notifications',
  };
  if (publishedPaths.length != expectedPaths.length ||
      !publishedPaths.containsAll(expectedPaths)) {
    failures.add(
      'apple-app-site-association paths must match the app router exactly: '
      '${expectedPaths.join(', ')}; got ${publishedPaths.join(', ')}.',
    );
  }
}

Future<String?> _expectSuccess(
  HttpClient client,
  String rawUrl,
  String label,
  List<String> failures, {
  bool allowRedirects = true,
  bool requireJsonContentType = false,
}) async {
  final uri = Uri.tryParse(rawUrl);
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
    failures.add('$label URL is not valid HTTPS: $rawUrl');
    return null;
  }
  try {
    final request = await client
        .getUrl(uri)
        .timeout(const Duration(seconds: 15));
    request.followRedirects = allowRedirects;
    request.maxRedirects = 3;
    final response = await request.close().timeout(const Duration(seconds: 20));
    final body = await utf8.decoder
        .bind(response)
        .join()
        .timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      failures.add('$label returned HTTP ${response.statusCode}: $rawUrl');
      return null;
    }
    if (!allowRedirects && response.redirects.isNotEmpty) {
      failures.add('$label must be served directly without redirects: $rawUrl');
      return null;
    }
    if (requireJsonContentType) {
      final contentType = response.headers.contentType;
      if (contentType?.mimeType.toLowerCase() != 'application/json') {
        failures.add(
          '$label must return Content-Type application/json, got '
          '${contentType?.mimeType ?? 'missing'}.',
        );
        return null;
      }
    }
    if (body.trim().isEmpty) {
      failures.add('$label returned an empty response: $rawUrl');
      return null;
    }
    return body;
  } on Object catch (error) {
    failures.add('$label is not publicly reachable with valid TLS: $error');
    return null;
  }
}

String _normalizeFingerprint(String value) =>
    value.replaceAll(':', '').trim().toUpperCase();

void _validateLegalDocumentVersions(
  String body, {
  required String expectedTermsVersion,
  required String expectedPrivacyVersion,
  required List<String> failures,
}) {
  try {
    final decoded = jsonDecode(body);
    final root = decoded is Map<String, dynamic>
        ? decoded
        : const <String, dynamic>{};
    final data = root['data'] is Map<String, dynamic>
        ? root['data'] as Map<String, dynamic>
        : root;
    final documents = data['documents'];
    final versions = <String, String>{};
    if (documents is List) {
      for (final document in documents) {
        if (document is! Map<String, dynamic>) continue;
        final type = '${document['document_type'] ?? document['type'] ?? ''}'
            .trim()
            .toLowerCase();
        final version = '${document['version'] ?? ''}'.trim();
        if (type.isNotEmpty && version.isNotEmpty) versions[type] = version;
      }
    }
    if (versions['terms'] != expectedTermsVersion) {
      failures.add(
        'Backend Terms version ${versions['terms'] ?? 'missing'} does not '
        'match configured version $expectedTermsVersion.',
      );
    }
    if (versions['privacy'] != expectedPrivacyVersion) {
      failures.add(
        'Backend Privacy version ${versions['privacy'] ?? 'missing'} does not '
        'match configured version $expectedPrivacyVersion.',
      );
    }
  } on FormatException catch (error) {
    failures.add('Backend legal-document response is not valid JSON: $error');
  }
}

void _finish(List<String> failures) {
  if (failures.isNotEmpty) {
    stderr.writeln('Public production endpoint validation failed:');
    for (final failure in failures) {
      stderr.writeln('- $failure');
    }
    exitCode = 1;
    return;
  }
  stdout.writeln('Public production endpoints and app associations validated.');
}

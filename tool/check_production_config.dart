import 'dart:io';

void main(List<String> arguments) {
  final argumentSet = arguments.toSet();
  final platform = argumentSet.contains('--platform=android')
      ? 'android'
      : argumentSet.contains('--platform=ios')
      ? 'ios'
      : '';
  final playSigningBootstrap = argumentSet.contains('--play-signing-bootstrap');
  if (platform.isEmpty) {
    stderr.writeln(
      'Usage: dart run tool/check_production_config.dart '
      '--platform=android|ios [--play-signing-bootstrap]',
    );
    exitCode = 64;
    return;
  }
  if (playSigningBootstrap && platform != 'android') {
    stderr.writeln('--play-signing-bootstrap is Android-only.');
    exitCode = 64;
    return;
  }
  final environment = Platform.environment;
  final failures = <String>[];

  String requireValue(String name) {
    final value = environment[name]?.trim() ?? '';
    if (value.isEmpty) {
      failures.add('$name is required for a production release.');
    }
    return value;
  }

  Uri? requireHttpsUrl(String name) {
    final raw = requireValue(name);
    final uri = Uri.tryParse(raw);
    if (raw.isNotEmpty &&
        (uri == null ||
            uri.scheme != 'https' ||
            uri.host.isEmpty ||
            uri.userInfo.isNotEmpty)) {
      failures.add('$name must be an absolute HTTPS URL without credentials.');
      return null;
    }
    if (_looksLikePlaceholder(raw)) {
      failures.add('$name must not contain a placeholder or example domain.');
    }
    if (uri != null && _isUnsafeProductionUri(uri)) {
      failures.add('$name must use a public production DNS host.');
    }
    return uri;
  }

  final apiBaseUrl = requireHttpsUrl('WEBTUI_API_BASE_URL');
  final privacyUrl = requireHttpsUrl('WEBTUI_PRIVACY_POLICY_URL');
  final termsUrl = requireHttpsUrl('WEBTUI_TERMS_URL');
  final deletionUrl = requireHttpsUrl('WEBTUI_ACCOUNT_DELETION_URL');
  requireHttpsUrl('WEBTUI_SUPPORT_URL');

  if (privacyUrl != null && termsUrl != null && privacyUrl == termsUrl) {
    failures.add('Privacy policy and Terms URLs must be different resources.');
  }
  if (privacyUrl != null && deletionUrl != null && privacyUrl == deletionUrl) {
    failures.add('Privacy policy and account-deletion URLs must be different.');
  }
  if (apiBaseUrl != null && apiBaseUrl.query.isNotEmpty) {
    failures.add('WEBTUI_API_BASE_URL must not contain a query string.');
  }
  if (apiBaseUrl != null &&
      apiBaseUrl.path.isNotEmpty &&
      apiBaseUrl.path != '/') {
    failures.add('WEBTUI_API_BASE_URL must be an HTTPS origin without a path.');
  }
  if (apiBaseUrl != null && apiBaseUrl.fragment.isNotEmpty) {
    failures.add('WEBTUI_API_BASE_URL must not contain a fragment.');
  }

  final appLinkHost = requireValue('WEBTUI_APP_LINK_HOST');
  if (appLinkHost.isNotEmpty &&
      (appLinkHost.contains('://') ||
          appLinkHost.contains('/') ||
          appLinkHost.contains('@') ||
          !appLinkHost.contains('.'))) {
    failures.add('WEBTUI_APP_LINK_HOST must be a DNS hostname only.');
  }
  if (_looksLikePlaceholder(appLinkHost)) {
    failures.add('WEBTUI_APP_LINK_HOST must not be a placeholder.');
  }
  if (appLinkHost.isNotEmpty && appLinkHost != 'chat.vpsttt.com') {
    failures.add(
      'WEBTUI_APP_LINK_HOST must match the associated-domain entitlement '
      'and production manifest host: chat.vpsttt.com.',
    );
  }

  final termsVersion = requireValue('WEBTUI_TERMS_VERSION');
  if (termsVersion.isNotEmpty &&
      !RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$').hasMatch(termsVersion)) {
    failures.add('WEBTUI_TERMS_VERSION has an invalid release identifier.');
  }
  final privacyVersion = requireValue('WEBTUI_PRIVACY_VERSION');
  if (privacyVersion.isNotEmpty &&
      !RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$').hasMatch(privacyVersion)) {
    failures.add('WEBTUI_PRIVACY_VERSION has an invalid release identifier.');
  }
  if (termsVersion.isNotEmpty &&
      privacyVersion.isNotEmpty &&
      termsVersion != privacyVersion) {
    failures.add(
      'Terms and Privacy versions must match the single version published by '
      'the production policy portal.',
    );
  }

  final firebaseApiKey = requireValue('FIREBASE_API_KEY');
  if (firebaseApiKey.isNotEmpty && !firebaseApiKey.startsWith('AIza')) {
    failures.add('FIREBASE_API_KEY does not look like a Firebase API key.');
  }
  final senderId = requireValue('FIREBASE_MESSAGING_SENDER_ID');
  if (senderId.isNotEmpty && !RegExp(r'^\d+$').hasMatch(senderId)) {
    failures.add('FIREBASE_MESSAGING_SENDER_ID must contain digits only.');
  }
  final firebaseProjectId = requireValue('FIREBASE_PROJECT_ID');
  if (_looksLikePlaceholder(firebaseProjectId)) {
    failures.add('FIREBASE_PROJECT_ID must not be a placeholder.');
  }
  if (platform == 'android') {
    final androidAppId = requireValue('FIREBASE_ANDROID_APP_ID');
    if (androidAppId.isNotEmpty &&
        !RegExp(r'^1:\d+:android:[A-Za-z0-9]+$').hasMatch(androidAppId)) {
      failures.add('FIREBASE_ANDROID_APP_ID has an invalid format.');
    }
  } else {
    final iosAppId = requireValue('FIREBASE_IOS_APP_ID');
    if (iosAppId.isNotEmpty &&
        !RegExp(r'^1:\d+:ios:[A-Za-z0-9]+$').hasMatch(iosAppId)) {
      failures.add('FIREBASE_IOS_APP_ID has an invalid format.');
    }
  }

  if (platform == 'android') {
    if (!playSigningBootstrap) {
      final fingerprints = requireValue('PLAY_APP_SIGNING_SHA256_FINGERPRINTS')
          .split(RegExp(r'[,;\n]+'))
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList(growable: false);
      final fingerprintPattern = RegExp(
        r'^(?:[0-9A-Fa-f]{2}:){31}[0-9A-Fa-f]{2}$',
      );
      if (fingerprints.isEmpty ||
          fingerprints.any((value) => !fingerprintPattern.hasMatch(value))) {
        failures.add(
          'PLAY_APP_SIGNING_SHA256_FINGERPRINTS must contain colon-separated '
          'Play App Signing SHA-256 fingerprints.',
        );
      }
      if (fingerprints.any(_looksLikePlaceholderFingerprint)) {
        failures.add(
          'PLAY_APP_SIGNING_SHA256_FINGERPRINTS contains a low-entropy '
          'placeholder rather than a Play App Signing certificate fingerprint.',
        );
      }
    }
    final keyStorePath = requireValue('ANDROID_KEYSTORE_PATH');
    requireValue('ANDROID_KEYSTORE_PASSWORD');
    final keyAlias = requireValue('ANDROID_KEY_ALIAS');
    requireValue('ANDROID_KEY_PASSWORD');
    final normalizedStorePath = keyStorePath.toLowerCase().replaceAll(
      '\\',
      '/',
    );
    final normalizedAlias = keyAlias.toLowerCase();
    if (normalizedStorePath.endsWith('/debug.keystore') ||
        normalizedStorePath == 'debug.keystore' ||
        normalizedAlias == 'androiddebugkey' ||
        normalizedAlias.contains('debug')) {
      failures.add(
        'Android production signing must not use the SDK debug keystore or '
        'a debug key alias.',
      );
    }
    if (keyStorePath.isNotEmpty) {
      final file = File(
        _isAbsolutePath(keyStorePath) ? keyStorePath : 'android/$keyStorePath',
      );
      if (!file.existsSync() ||
          file.statSync().type != FileSystemEntityType.file) {
        failures.add(
          'ANDROID_KEYSTORE_PATH does not point to an existing file.',
        );
      }
    }
  } else {
    final appleTeamId = requireValue('APPLE_TEAM_ID');
    if (appleTeamId.isNotEmpty &&
        !RegExp(r'^[A-Z0-9]{10}$').hasMatch(appleTeamId)) {
      failures.add('APPLE_TEAM_ID must be the 10-character Apple team ID.');
    }
    final appleBundleId = requireValue('APPLE_BUNDLE_ID');
    if (appleBundleId.isNotEmpty && appleBundleId != 'com.vpsttt.webtuiChat') {
      failures.add(
        'APPLE_BUNDLE_ID must match the permanent Xcode bundle ID '
        'com.vpsttt.webtuiChat.',
      );
    }
  }

  if (failures.isNotEmpty) {
    stderr.writeln('Production configuration is incomplete:');
    for (final failure in failures) {
      stderr.writeln('- $failure');
    }
    exitCode = 1;
    return;
  }

  stdout.writeln(
    playSigningBootstrap
        ? 'Play signing bootstrap configuration validated; this artifact must '
              'remain Internal-only and must never be promoted.'
        : 'Production configuration validated without exposing secrets.',
  );
}

bool _looksLikePlaceholder(String value) {
  final normalized = value.toLowerCase();
  return normalized.contains('example.') ||
      normalized.contains('<') ||
      normalized.contains('>') ||
      normalized.contains('your-') ||
      normalized.contains('placeholder') ||
      normalized.endsWith('.invalid') ||
      normalized.endsWith('.test');
}

bool _looksLikePlaceholderFingerprint(String value) {
  final compact = value.replaceAll(':', '').toUpperCase();
  if (compact.length != 64) return false;
  final bytes = <String>{
    for (var index = 0; index < compact.length; index += 2)
      compact.substring(index, index + 2),
  };
  // A real SHA-256 certificate digest having fewer than four distinct bytes
  // is vanishingly unlikely; repeated 00/11/AA/FF fixtures are common release
  // placeholders and must not satisfy a syntactic-only gate.
  return bytes.length < 4;
}

bool _isUnsafeProductionUri(Uri uri) {
  final host = uri.host.toLowerCase();
  if (host.isEmpty ||
      host == 'localhost' ||
      host.endsWith('.localhost') ||
      host.endsWith('.local') ||
      !host.contains('.')) {
    return true;
  }
  final address = InternetAddress.tryParse(host);
  if (address == null) return false;
  if (address.isLoopback || address.isLinkLocal || address.isMulticast) {
    return true;
  }
  final bytes = address.rawAddress;
  if (address.type == InternetAddressType.IPv4) {
    return bytes[0] == 0 ||
        bytes[0] == 10 ||
        bytes[0] == 127 ||
        (bytes[0] == 169 && bytes[1] == 254) ||
        (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
        (bytes[0] == 192 && bytes[1] == 168) ||
        bytes[0] >= 224;
  }
  return bytes.isNotEmpty && (bytes[0] & 0xfe) == 0xfc;
}

bool _isAbsolutePath(String path) =>
    path.startsWith('/') || RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path);

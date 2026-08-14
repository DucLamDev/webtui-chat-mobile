import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_flavor.dart';

final appConfigProvider = Provider<AppConfig>((_) {
  throw StateError('AppConfig must be provided from bootstrap.');
});

final class AppConfig {
  const AppConfig({
    required this.flavor,
    required this.apiBaseUri,
    required this.wsBaseUri,
    this.appVersion = '1.0.0',
    this.releaseChannel = 'internal',
    this.releaseServiceBaseUrl = 'https://download.webtui.vn',
    this.termsUrl = 'https://download.webtui.vn/terms',
    this.privacyPolicyUrl = 'https://download.webtui.vn/privacy',
    this.termsVersion = '2026-08-07',
    this.privacyPolicyVersion = '2026-08-07',
  });

  factory AppConfig.fromFlavor(AppFlavor flavor) {
    const configuredBaseUrl = String.fromEnvironment(
      'WEBTUI_API_BASE_URL',
      defaultValue: '',
    );
    const configuredWsUrl = String.fromEnvironment(
      'WEBTUI_WS_BASE_URL',
      defaultValue: '',
    );
    const configuredAppVersion = String.fromEnvironment(
      'WEBTUI_APP_VERSION',
      defaultValue: '1.0.0',
    );
    const configuredReleaseChannel = String.fromEnvironment(
      'WEBTUI_RELEASE_CHANNEL',
      defaultValue: '',
    );
    const configuredReleaseServiceUrl = String.fromEnvironment(
      'WEBTUI_RELEASE_SERVICE_URL',
      defaultValue: 'https://download.webtui.vn',
    );
    const configuredTermsUrl = String.fromEnvironment(
      'WEBTUI_TERMS_URL',
      defaultValue: 'https://download.webtui.vn/terms',
    );
    const configuredPrivacyPolicyUrl = String.fromEnvironment(
      'WEBTUI_PRIVACY_POLICY_URL',
      defaultValue: 'https://download.webtui.vn/privacy',
    );
    const configuredTermsVersion = String.fromEnvironment(
      'WEBTUI_TERMS_VERSION',
      defaultValue: '2026-08-07',
    );
    const configuredPrivacyPolicyVersion = String.fromEnvironment(
      'WEBTUI_PRIVACY_VERSION',
      defaultValue: '2026-08-07',
    );

    final apiBaseUri = configuredBaseUrl.isEmpty
        ? flavor.defaultApiBaseUri
        : Uri.parse(configuredBaseUrl);

    return AppConfig(
      flavor: flavor,
      apiBaseUri: apiBaseUri,
      wsBaseUri: configuredWsUrl.isEmpty
          ? _defaultRealtimeWsUri(apiBaseUri)
          : Uri.parse(configuredWsUrl),
      appVersion: configuredAppVersion,
      releaseChannel: configuredReleaseChannel.isEmpty
          ? _defaultReleaseChannel(flavor)
          : configuredReleaseChannel,
      releaseServiceBaseUrl: configuredReleaseServiceUrl,
      termsUrl: configuredTermsUrl,
      privacyPolicyUrl: configuredPrivacyPolicyUrl,
      termsVersion: configuredTermsVersion,
      privacyPolicyVersion: configuredPrivacyPolicyVersion,
    );
  }

  final AppFlavor flavor;
  final Uri apiBaseUri;
  final Uri wsBaseUri;
  final String appVersion;
  final String releaseChannel;
  // Publisher-controlled release origin. It deliberately does not change when
  // the user connects to a different self-hosted instance.
  final String releaseServiceBaseUrl;
  final String termsUrl;
  final String privacyPolicyUrl;
  final String termsVersion;
  final String privacyPolicyVersion;

  bool get hasPublicLegalUrls =>
      _isPublicHttpsUrl(termsUrl) && _isPublicHttpsUrl(privacyPolicyUrl);

  AppConfig forServer(Uri serverUri, {Uri? wsBaseUri}) {
    return AppConfig(
      flavor: flavor,
      apiBaseUri: serverUri,
      wsBaseUri: wsBaseUri ?? _defaultRealtimeWsUri(serverUri),
      appVersion: appVersion,
      releaseChannel: releaseChannel,
      releaseServiceBaseUrl: releaseServiceBaseUrl,
      termsUrl: termsUrl,
      privacyPolicyUrl: privacyPolicyUrl,
      termsVersion: termsVersion,
      privacyPolicyVersion: privacyPolicyVersion,
    );
  }

  String get appTitle {
    return 'WebTUI Chat';
  }

  bool get showDebugBanner => flavor != AppFlavor.prod;
}

bool _isPublicHttpsUrl(String value) {
  final uri = Uri.tryParse(value.trim());
  return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty;
}

Uri _defaultRealtimeWsUri(Uri apiBaseUri) {
  final scheme = apiBaseUri.scheme == 'https' ? 'wss' : 'ws';
  return Uri(
    scheme: scheme,
    userInfo: apiBaseUri.userInfo,
    host: apiBaseUri.host,
    port: apiBaseUri.hasPort ? apiBaseUri.port : null,
    path: '/ws',
  );
}

String _defaultReleaseChannel(AppFlavor flavor) {
  return switch (flavor) {
    AppFlavor.dev => 'internal',
    AppFlavor.staging => 'beta',
    AppFlavor.prod => 'stable',
  };
}

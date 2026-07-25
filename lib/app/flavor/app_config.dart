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
    );
  }

  final AppFlavor flavor;
  final Uri apiBaseUri;
  final Uri wsBaseUri;
  final String appVersion;
  final String releaseChannel;

  AppConfig forServer(Uri serverUri, {Uri? wsBaseUri}) {
    return AppConfig(
      flavor: flavor,
      apiBaseUri: serverUri,
      wsBaseUri: wsBaseUri ?? _defaultRealtimeWsUri(serverUri),
      appVersion: appVersion,
      releaseChannel: releaseChannel,
    );
  }

  String get appTitle {
    return 'Webtui Chat';
  }

  bool get showDebugBanner => flavor != AppFlavor.prod;
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

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/network/self_hosted_server_discovery.dart';
import '../core/network/self_hosted_server_uri.dart';
import '../core/notifications/native_incoming_call_service.dart';
import '../core/notifications/push_notification_service.dart';
import '../core/security/secure_key_value_store.dart';
import 'app.dart';
import 'flavor/app_config.dart';
import 'flavor/app_flavor.dart';
import 'providers/foundation_providers.dart';

Future<void> bootstrap({required AppFlavor flavor}) async {
  WidgetsFlutterBinding.ensureInitialized();
  configureFirebaseBackgroundMessaging();
  NativeIncomingCallService.ensureStarted();
  await ensureFirebaseRuntime();

  var config = AppConfig.fromFlavor(flavor);
  const secureStorage = FlutterSecureStorage();
  final storedServer = await secureStorage.read(
    key: SecureStoreKey.instanceBaseUrl.value,
  );
  final storedWebSocket = await secureStorage.read(
    key: SecureStoreKey.instanceWsBaseUrl.value,
  );
  final storedOrganizationName = await secureStorage.read(
    key: SecureStoreKey.instanceOrganizationName.value,
  );
  final storedOrganizationLogoUrl = await secureStorage.read(
    key: SecureStoreKey.instanceOrganizationLogoUrl.value,
  );
  final storedRegistrationMode = await secureStorage.read(
    key: SecureStoreKey.instanceRegistrationMode.value,
  );
  final storedAppVersion = await secureStorage.read(
    key: SecureStoreKey.instanceAppVersion.value,
  );
  SelfHostedServerDiscovery? initialDiscovery;
  if (storedServer != null) {
    try {
      final serverUri = parseSelfHostedServerUri(storedServer);
      final wsUri = storedWebSocket == null
          ? null
          : parseSelfHostedWebSocketUri(storedWebSocket);
      if (wsUri != null &&
          wsUri.host.toLowerCase() != serverUri.host.toLowerCase()) {
        throw const FormatException(
          'WebSocket đã lưu không thuộc server đang active.',
        );
      }
      config = config.forServer(serverUri, wsBaseUri: wsUri);
      initialDiscovery = SelfHostedServerDiscovery(
        domain: serverUri.host,
        name: storedOrganizationName?.trim().isNotEmpty == true
            ? storedOrganizationName!.trim()
            : serverUri.host,
        apiBaseUri: config.apiBaseUri,
        wsBaseUri: config.wsBaseUri,
        registrationMode: storedRegistrationMode?.trim().isNotEmpty == true
            ? storedRegistrationMode!.trim()
            : 'closed',
        appVersion: storedAppVersion?.trim() ?? '',
        logoUrl: _validatedCachedLogoUrl(storedOrganizationLogoUrl),
      );
    } on FormatException {
      await _clearStoredServer(secureStorage);
    }
  } else if (storedWebSocket != null) {
    await _clearStoredServer(secureStorage);
  }

  runApp(
    ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(config),
        initialServerDiscoveryProvider.overrideWithValue(initialDiscovery),
      ],
      child: const WebTuiChatApp(),
    ),
  );
}

String? _validatedCachedLogoUrl(String? value) {
  final parsed = Uri.tryParse(value?.trim() ?? '');
  if (parsed == null || parsed.host.isEmpty || parsed.userInfo.isNotEmpty) {
    return null;
  }
  final isLocal =
      parsed.host == 'localhost' ||
      parsed.host == '127.0.0.1' ||
      parsed.host.endsWith('.localhost');
  if (parsed.scheme != 'https' && !(isLocal && parsed.scheme == 'http')) {
    return null;
  }
  return parsed.toString();
}

Future<void> _clearStoredServer(FlutterSecureStorage storage) async {
  await Future.wait(
    [
      SecureStoreKey.instanceBaseUrl,
      SecureStoreKey.instanceWsBaseUrl,
      SecureStoreKey.instanceOrganizationName,
      SecureStoreKey.instanceOrganizationLogoUrl,
      SecureStoreKey.instanceRegistrationMode,
      SecureStoreKey.instanceAppVersion,
    ].map((key) => storage.delete(key: key.value)),
  );
}

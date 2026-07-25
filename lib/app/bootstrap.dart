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
    } on FormatException {
      await secureStorage.delete(key: SecureStoreKey.instanceBaseUrl.value);
      await secureStorage.delete(key: SecureStoreKey.instanceWsBaseUrl.value);
    }
  } else if (storedWebSocket != null) {
    await secureStorage.delete(key: SecureStoreKey.instanceWsBaseUrl.value);
  }

  runApp(
    ProviderScope(
      overrides: [appConfigProvider.overrideWithValue(config)],
      child: const WebTuiChatApp(),
    ),
  );
}

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import '../core/network/self_hosted_server_discovery.dart';
import '../core/network/self_hosted_server_discovery_client.dart';
import '../core/notifications/native_incoming_call_service.dart';
import '../core/notifications/push_notification_service.dart';
import '../core/notifications/scoped_local_notification_service.dart';
import '../core/platform/native_instance_binding_service.dart';
import '../core/security/secure_key_value_store.dart';
import '../core/security/server_account_registry.dart';
import 'app.dart';
import 'flavor/app_config.dart';
import 'flavor/app_flavor.dart';
import 'providers/foundation_providers.dart';

Future<void> bootstrap({required AppFlavor flavor}) async {
  WidgetsFlutterBinding.ensureInitialized();
  await ScopedLocalNotificationService.instance.initialize();
  await ScopedLocalNotificationService.instance.clearMessageNotifications(
    clearPendingTaps: false,
  );
  configureFirebaseBackgroundMessaging();
  NativeIncomingCallService.ensureStarted();
  await NativeIncomingCallService.registerBackgroundActionHandler();
  // Push setup is not required to draw the first frame. The notification
  // service awaits the same idempotent initializer before it reads a token.
  unawaited(ensureFirebaseRuntime());

  var config = AppConfig.fromFlavor(flavor);
  const secureStorage = FlutterSecureStorage();
  const secureStore = FlutterSecureKeyValueStore(secureStorage);
  const serverAccountRegistry = SecureServerAccountRegistry(secureStore);
  const nativeInstanceBinding = NativeInstanceBindingService();
  // A prior process's successful check is never authoritative for a new cold
  // start: the server may have raised its minimum mobile version or disabled a
  // mandatory safety capability in the meantime.
  await secureStorage.delete(
    key: SecureStoreKey.liveDiscoveryValidatedScopeId.value,
  );
  final storedValues = await Future.wait<String?>([
    secureStorage.read(key: SecureStoreKey.instanceDiscoverySnapshot.value),
    secureStorage.read(key: SecureStoreKey.instanceId.value),
    secureStorage.read(key: SecureStoreKey.activeInstanceScopeId.value),
    secureStorage.read(key: SecureStoreKey.sessionPersistence.value),
  ]);
  final storedSnapshot = storedValues[0];
  final storedInstanceId = storedValues[1];
  final storedScopeId = storedValues[2];
  SelfHostedServerDiscovery? initialDiscovery;
  if (storedSnapshot != null && storedSnapshot.trim().isNotEmpty) {
    SelfHostedServerDiscovery? cachedDiscovery;
    try {
      cachedDiscovery = SelfHostedServerDiscovery.fromStorageSnapshot(
        encodedSnapshot: storedSnapshot,
        mobileVersion: config.appVersion,
      );
      if (storedInstanceId != cachedDiscovery.instanceId ||
          storedScopeId != cachedDiscovery.instanceScope.storageId) {
        throw const FormatException('Stored instance binding is invalid.');
      }
    } on Object {
      await _clearStoredServer(secureStorage);
      await nativeInstanceBinding.clear();
    }
    if (cachedDiscovery != null) {
      try {
        final liveDiscovery = await SelfHostedServerDiscoveryClient(
          mobileVersion: config.appVersion,
        ).discover(cachedDiscovery.apiBaseUri.toString());
        if (liveDiscovery.instanceScope != cachedDiscovery.instanceScope) {
          throw StateError('Live discovery instance binding changed.');
        }
        await secureStorage.write(
          key: SecureStoreKey.instanceDiscoverySnapshot.value,
          value: liveDiscovery.toStorageSnapshot(),
        );
        await secureStorage.write(
          key: SecureStoreKey.liveDiscoveryValidatedScopeId.value,
          value: liveDiscovery.instanceScope.storageId,
        );
        await secureStorage.write(
          key: SecureStoreKey.activeInstanceGeneration.value,
          value: const Uuid().v4(),
        );
        final durableSession =
            storedValues[3] == durableSessionPersistenceValue &&
            await serverAccountRegistry.hasDurableSessionForScopeId(
              liveDiscovery.instanceScope.storageId,
            );
        await nativeInstanceBinding.setValidatedInstance(
          liveDiscovery.instanceScope,
          durableSession: durableSession,
        );
        config = config.forServer(
          liveDiscovery.apiBaseUri,
          wsBaseUri: liveDiscovery.wsBaseUri,
        );
        initialDiscovery = liveDiscovery;
      } on Object {
        // Keep the signed snapshot/account record for a later retry, but do not
        // expose its tokens or construct authenticated providers in this run.
        initialDiscovery = null;
      }
    }
  } else {
    // Legacy releases stored an origin but not the server-signed instance
    // identity/capabilities. Those sessions cannot be safely restored.
    await _clearStoredServer(secureStorage);
    await nativeInstanceBinding.clear();
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

Future<void> _clearStoredServer(FlutterSecureStorage storage) async {
  await Future.wait(
    [
      SecureStoreKey.instanceBaseUrl,
      SecureStoreKey.instanceWsBaseUrl,
      SecureStoreKey.instanceOrganizationName,
      SecureStoreKey.instanceOrganizationLogoUrl,
      SecureStoreKey.instanceRegistrationMode,
      SecureStoreKey.instanceAppVersion,
      SecureStoreKey.instanceId,
      SecureStoreKey.activeInstanceScopeId,
      SecureStoreKey.liveDiscoveryValidatedScopeId,
      SecureStoreKey.activeInstanceGeneration,
      SecureStoreKey.instanceDiscoverySnapshot,
      SecureStoreKey.accessToken,
      SecureStoreKey.refreshToken,
      SecureStoreKey.sessionInstanceScopeId,
      SecureStoreKey.sessionPersistence,
      SecureStoreKey.activeWorkspaceId,
      SecureStoreKey.activeWorkspaceInstanceScopeId,
    ].map((key) => storage.delete(key: key.value)),
  );
}

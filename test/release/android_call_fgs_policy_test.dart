import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  String source(String path) => File(path).readAsStringSync();

  test('first Play release contains no screen capture implementation', () {
    final pubspec = source('pubspec.yaml');
    final manifest = source('android/app/src/main/AndroidManifest.xml');
    final callScreen = source(
      'lib/features/conversations/presentation/screens/webrtc_call_screen.dart',
    );

    expect(pubspec, isNot(contains('flutter_background:')));
    expect(pubspec, contains('path: third_party/flutter_callkit_incoming'));
    expect(manifest, isNot(contains('FOREGROUND_SERVICE_MEDIA_PROJECTION')));
    expect(
      manifest,
      isNot(contains('foregroundServiceType="mediaProjection"')),
    );
    expect(
      manifest,
      isNot(contains('flutter_background.IsolateHolderService')),
    );
    expect(callScreen, isNot(contains('getDisplayMedia')));
    expect(callScreen.toLowerCase(), isNot(contains('screenshare')));
  });

  test('outgoing lifecycle begins after contextual media permission flow', () {
    final callScreen = source(
      'lib/features/conversations/presentation/screens/webrtc_call_screen.dart',
    );
    final permissionBoundary = callScreen.indexOf('getUserMedia');
    final outgoingStart = callScreen.indexOf(
      'NativeIncomingCallService.startOutgoingCall',
    );

    expect(permissionBoundary, greaterThanOrEqualTo(0));
    expect(outgoingStart, greaterThan(permissionBoundary));
    expect(
      RegExp('NativeIncomingCallService\\.endCall').allMatches(callScreen),
      hasLength(greaterThanOrEqualTo(2)),
    );
  });

  test('vendored CallKit fork starts phoneCall-only then guards promotion', () {
    final service = source(
      'third_party/flutter_callkit_incoming/android/src/main/kotlin/'
      'com/hiennv/flutter_callkit_incoming/CallkitNotificationService.kt',
    );
    final plugin = source(
      'third_party/flutter_callkit_incoming/android/src/main/kotlin/'
      'com/hiennv/flutter_callkit_incoming/FlutterCallkitIncomingPlugin.kt',
    );
    final receiver = source(
      'third_party/flutter_callkit_incoming/android/src/main/kotlin/'
      'com/hiennv/flutter_callkit_incoming/CallkitIncomingBroadcastReceiver.kt',
    );
    final managerProvider = source(
      'third_party/flutter_callkit_incoming/android/src/main/kotlin/'
      'com/hiennv/flutter_callkit_incoming/'
      'CallkitNotificationManagerProvider.kt',
    );
    final pendingStore = source(
      'third_party/flutter_callkit_incoming/android/src/main/kotlin/'
      'com/hiennv/flutter_callkit_incoming/CallkitPendingActionStore.kt',
    );
    final connection = source(
      'third_party/flutter_callkit_incoming/android/src/main/kotlin/'
      'com/hiennv/flutter_callkit_incoming/CallkitConnection.kt',
    );
    final connectionService = source(
      'third_party/flutter_callkit_incoming/android/src/main/kotlin/'
      'com/hiennv/flutter_callkit_incoming/CallkitConnectionService.kt',
    );
    final backgroundExecutor = source(
      'third_party/flutter_callkit_incoming/android/src/main/kotlin/'
      'com/hiennv/flutter_callkit_incoming/CallkitBackgroundExecutor.kt',
    );
    final pendingWorker = source(
      'third_party/flutter_callkit_incoming/android/src/main/kotlin/'
      'com/hiennv/flutter_callkit_incoming/CallkitPendingActionWorker.kt',
    );
    final receiverLease = source(
      'third_party/flutter_callkit_incoming/android/src/main/kotlin/'
      'com/hiennv/flutter_callkit_incoming/CallkitReceiverExecutionLease.kt',
    );
    final pluginBuild = source(
      'third_party/flutter_callkit_incoming/android/build.gradle',
    );
    final nativeCallService = source(
      'lib/core/notifications/native_incoming_call_service.dart',
    );
    final bootstrap = source('lib/app/bootstrap.dart');
    final pluginManifest = source(
      'third_party/flutter_callkit_incoming/android/src/main/AndroidManifest.xml',
    );

    final initialStart = service.substring(
      service.indexOf('private fun startPhoneCallForeground'),
      service.indexOf('private fun promoteMediaForeground'),
    );
    expect(initialStart, contains('FOREGROUND_SERVICE_TYPE_PHONE_CALL'));
    expect(initialStart, isNot(contains('FOREGROUND_SERVICE_TYPE_MICROPHONE')));
    expect(initialStart, isNot(contains('FOREGROUND_SERVICE_TYPE_CAMERA')));

    expect(service, contains('Manifest.permission.RECORD_AUDIO'));
    expect(service, contains('Manifest.permission.CAMERA'));
    expect(service, contains('IMPORTANCE_FOREGROUND'));
    expect(service, contains('IMPORTANCE_VISIBLE'));
    expect(service, contains('CallkitNotificationManagerProvider.get'));
    expect(receiver, contains('CallkitNotificationManagerProvider.get'));
    expect(
      service,
      isNot(contains('FlutterCallkitIncomingPlugin.getInstance')),
    );
    expect(
      receiver,
      isNot(contains('FlutterCallkitIncomingPlugin.getInstance')),
    );
    expect(managerProvider, contains('context.applicationContext'));
    expect(managerProvider, contains('CallkitNotificationManager('));
    expect(managerProvider, contains('CallkitSoundPlayerManager('));
    expect(
      managerProvider.indexOf('processManager?.let { return it }'),
      lessThan(
        managerProvider.indexOf('FlutterCallkitIncomingPlugin.getInstance'),
      ),
      reason: 'a cold fallback must never switch sound-player instances',
    );
    expect(
      service,
      contains(
        'private fun getCallkitNotificationManager(): CallkitNotificationManager',
      ),
    );
    expect(
      service,
      isNot(
        contains('getCallkitNotificationManager()?.getOnGoingCallNotification'),
      ),
    );
    expect(
      receiver,
      contains(
        'private fun getCallkitNotificationManager(context: Context): '
        'CallkitNotificationManager',
      ),
    );
    expect(receiver, isNot(contains('getCallkitNotificationManager()?.')));
    expect(receiver, isNot(contains('notificationManager?.')));
    expect(service, isNot(contains('intent?.action ===')));
    expect(
      RegExp(
        r'intent\?\.action == CallkitConstants\.ACTION_CALL_',
      ).allMatches(service),
      hasLength(3),
    );
    expect(plugin, contains('MEDIA_PERMISSION_REQUIRED'));
    expect(plugin, contains('"activateCallMedia"'));
    expect(plugin, contains('CallkitNotificationService.stopService'));
    expect(plugin, contains('"getPendingCallActions"'));
    expect(plugin, contains('"ackPendingCallAction"'));
    expect(receiver, contains('CallkitPendingActionStore.record'));
    expect(receiver, contains('CallkitPendingActionWorker.enqueue'));
    expect(receiver, contains('CallkitReceiverExecutionLease.hold'));
    expect(receiver, contains('goAsync()'));
    expect(pendingStore, contains('.commit()'));
    expect(pendingStore, contains('ACTION_CALL_ACCEPT'));
    expect(pendingStore, contains('ACTION_CALL_DECLINE'));
    expect(pendingStore, contains('ACTION_CALL_ENDED'));
    expect(pendingStore, contains('ACTION_CALL_TIMEOUT'));
    expect(pendingStore, contains('server_base_url'));
    expect(pendingStore, contains('put("instance_id", instanceId)'));
    expect(pendingStore, contains('instanceIdPattern.matches(instanceId)'));
    expect(
      pendingStore,
      contains(r'"$event:$instanceId:$callId"'),
      reason: 'same call UUIDs on two instances must not overwrite each other',
    );
    expect(pendingStore, isNot(contains('caller_name')));
    expect(pendingStore, isNot(contains('logo_url')));
    expect(pendingStore, isNot(contains('deep_link')));
    expect(
      connection,
      contains('emitTelecomAction(CallkitConstants.ACTION_CALL_ACCEPT)'),
    );
    expect(
      connection,
      contains('emitTelecomAction(CallkitConstants.ACTION_CALL_DECLINE)'),
    );
    expect(
      RegExp(
        r'emitTelecomAction\(CallkitConstants\.ACTION_CALL_ENDED\)',
      ).allMatches(connection),
      hasLength(2),
    );
    expect(connection, contains('EXTRA_ACTION_FROM_TELECOM'));
    expect(
      connectionService,
      contains('applicationContext, callId, callBundle'),
    );
    expect(backgroundExecutor, contains('getPluginCallbackHandle(context)'));
    expect(backgroundExecutor, contains('pendingEvents.add'));
    expect(backgroundExecutor, contains('call.method == "initialized"'));
    expect(backgroundExecutor, contains('flushLocked()'));
    expect(backgroundExecutor, contains('90_000L'));
    expect(
      backgroundExecutor.indexOf('backgroundChannel = MethodChannel('),
      lessThan(backgroundExecutor.indexOf('executeDartCallback(args)')),
      reason: 'native readiness handler must exist before Dart starts',
    );
    expect(receiverLease, contains('MAX_LEASE_MS = 9_000L'));
    expect(receiverLease, contains('PendingResult'));
    expect(pendingWorker, contains('CoroutineWorker'));
    expect(pendingWorker, contains('NetworkType.CONNECTED'));
    expect(pendingWorker, isNot(contains('setExpedited')));
    expect(pendingWorker, contains('setInitialDelay(10L'));
    expect(pendingWorker, contains('Dispatchers.Main.immediate'));
    expect(pendingWorker, contains('ExistingWorkPolicy.KEEP'));
    expect(pendingWorker, contains('KEY_INSTANCE_ID = "instance_id"'));
    expect(
      pendingWorker,
      contains('.putString(KEY_INSTANCE_ID, extra.stringValue("instance_id")'),
    );
    expect(pendingWorker, contains('"instance_id" to instanceId'));
    expect(pendingWorker, contains('completion.await()'));
    expect(pendingWorker, contains('Result.retry()'));
    expect(pluginBuild, contains('work-runtime-ktx:2.10.5'));
    expect(
      plugin.substring(
        plugin.indexOf('"registerBackgroundHandler"'),
        plugin.indexOf('"getBackgroundHandler"'),
      ),
      isNot(contains('CallkitBackgroundExecutor.start')),
      reason: 'registration must not keep an auxiliary engine alive',
    );
    expect(bootstrap, contains('registerBackgroundActionHandler'));
    expect(
      nativeCallService,
      contains(
        "@pragma('vm:entry-point')\n"
        'Future<void> webTuiCallkitBackgroundHandler',
      ),
    );
    expect(nativeCallService, contains('SecureStoreKey.activeWorkspaceId'));
    expect(nativeCallService, contains('backgroundCallBindingMatches'));
    expect(nativeCallService, contains('request.followRedirects = false'));
    expect(nativeCallService, isNot(contains("path: '/api/v1/auth/refresh'")));
    expect(
      nativeCallService,
      isNot(contains('SecureStoreKey.refreshToken')),
      reason:
          'headless refresh rotation cannot be committed atomically with foreground state',
    );
    expect(nativeCallService, contains('acknowledge(action)'));
    expect(nativeCallService, contains("'instance_id': binding.instanceId"));
    expect(
      nativeCallService,
      contains("'server_base_url': binding.serverBaseUrl"),
    );
    expect(
      nativeCallService,
      contains('scopeId != values[3]?.trim()'),
      reason: 'outgoing calls require current live discovery validation',
    );
    expect(
      nativeCallService,
      contains(
        'if (action.type == NativeIncomingCallActionType.accept) return;',
      ),
      reason: 'accept must be handed to visible WebRTC/media setup',
    );
    expect(receiver, contains('foregroundAcceptedTelecomCall'));
    expect(
      receiver,
      contains('Unable to foreground accepted Telecom call'),
      reason: 'OEM activity-launch rejection must not abort durable replay',
    );

    expect(pluginManifest, contains('FOREGROUND_SERVICE_PHONE_CALL'));
    expect(pluginManifest, contains('FOREGROUND_SERVICE_MICROPHONE'));
    expect(pluginManifest, contains('FOREGROUND_SERVICE_CAMERA'));
    expect(
      pluginManifest,
      contains('foregroundServiceType="phoneCall|microphone|camera"'),
    );
  });

  test('Play copy does not claim media projection or screen sharing', () {
    final declaration = source(
      'store/google-play/foreground-service-declaration.md',
    );
    final listing = source('store/google-play/listing-vi.md');

    expect(declaration, isNot(contains('mediaProjection')));
    expect(declaration.toLowerCase(), isNot(contains('screen sharing')));
    expect(listing.toLowerCase(), isNot(contains('chia sẻ màn hình')));
  });
}

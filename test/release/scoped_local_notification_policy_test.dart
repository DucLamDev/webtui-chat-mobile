import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  String source(String path) => File(path).readAsStringSync();

  test('Play data-only notification renderer is pinned and desugared', () {
    final pubspec = source('pubspec.yaml');
    final gradle = source('android/app/build.gradle.kts');

    expect(pubspec, contains('flutter_local_notifications: 22.2.0'));
    expect(gradle, contains('isCoreLibraryDesugaringEnabled = true'));
    expect(
      gradle,
      contains(
        'coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")',
      ),
    );
  });

  test('ordinary Android notifications are private and never full-screen', () {
    final localService = source(
      'lib/core/notifications/scoped_local_notification_service.dart',
    );
    final manifest = source('android/app/src/main/AndroidManifest.xml');

    expect(localService, contains('NotificationVisibility.private'));
    expect(localService, contains('fullScreenIntent: false'));
    expect(localService, contains('icon: _notificationIcon'));
    expect(localService, contains('tag: notification.tag'));
    expect(
      localService,
      isNot(contains('encodedRoutingPayload: jsonEncode(data)')),
      reason: 'title/body and other PII must not be copied into tap payloads',
    );
    expect(manifest, contains('@drawable/ic_stat_webtui_chat'));
    expect(manifest, contains('webtui_messages'));
    expect(localService, contains('messageNotificationCancelTargets'));
    expect(localService, isNot(contains('_plugin.cancelAll()')));
  });

  test('display and tap paths both require persisted scope validation', () {
    final pushService = source(
      'lib/core/notifications/push_notification_service.dart',
    );

    expect(pushService, contains('displayScopedDataOnlyNotification('));
    expect(pushService, contains('requireDurableSession: true'));
    expect(pushService, contains('SecureStoreKey.sessionInstanceScopeId'));
    expect(
      pushService,
      contains('SecureStoreKey.activeWorkspaceInstanceScopeId'),
    );
    expect(pushService, contains('SecureStoreKey.activeInstanceGeneration'));
    expect(pushService, contains('SecureStoreKey.sessionPersistence'));
  });

  test(
    'message handlers resolve the currently registered workspace per event',
    () {
      final pushService = source(
        'lib/core/notifications/push_notification_service.dart',
      );

      expect(pushService, contains('_startMessageHandlers();'));
      expect(
        pushService,
        isNot(contains('_startMessageHandlers(normalizedWorkspaceId)')),
      );
      expect(
        pushService,
        contains('final workspaceId = _currentRegisteredWorkspaceId;'),
      );
      expect(
        pushService,
        isNot(contains('_registeredWorkspaceId ?? normalizedWorkspaceId')),
      );
    },
  );
}

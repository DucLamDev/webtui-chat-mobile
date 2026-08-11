import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('workspace registration never triggers a notification prompt', () {
    final source = File(
      'lib/core/notifications/push_notification_service.dart',
    ).readAsStringSync();
    final registrationStart = source.indexOf(
      'Future<void> registerForWorkspace',
    );
    final statusStart = source.indexOf(
      'Future<String> notificationPermissionStatus',
    );
    expect(registrationStart, greaterThanOrEqualTo(0));
    expect(statusStart, greaterThan(registrationStart));

    final registrationBody = source.substring(registrationStart, statusStart);
    expect(registrationBody, isNot(contains('_requestPermission()')));
    expect(registrationBody, isNot(contains('prepareDevicePermissions()')));
  });

  test('permission prompt is isolated behind an explicit user action API', () {
    final source = File(
      'lib/core/notifications/push_notification_service.dart',
    ).readAsStringSync();
    final explicitActionStart = source.indexOf(
      'Future<String> requestNotificationPermissionForWorkspace',
    );
    final unregisterStart = source.indexOf('Future<void> unregister()');
    expect(explicitActionStart, greaterThanOrEqualTo(0));
    expect(unregisterStart, greaterThan(explicitActionStart));

    final explicitAction = source.substring(
      explicitActionStart,
      unregisterStart,
    );
    expect(explicitAction, contains('_requestPermission()'));
    expect(explicitAction, contains('prepareDevicePermissions()'));
  });
}

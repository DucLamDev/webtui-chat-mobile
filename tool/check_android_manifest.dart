import 'dart:io';

const _forbiddenPermissions = <String>{
  'android.permission.ACCESS_BACKGROUND_LOCATION',
  'android.permission.ACCESS_COARSE_LOCATION',
  'android.permission.ACCESS_FINE_LOCATION',
  'android.permission.ACCESS_NOTIFICATION_POLICY',
  'android.permission.MANAGE_EXTERNAL_STORAGE',
  // Screen sharing is intentionally disabled for the first Play release.
  // Reintroducing this permission requires a consent-first native flow and a
  // new foreground-service declaration/reviewer evidence set.
  'android.permission.FOREGROUND_SERVICE_MEDIA_PROJECTION',
  'android.permission.QUERY_ALL_PACKAGES',
  'android.permission.READ_CALL_LOG',
  'android.permission.READ_CONTACTS',
  'android.permission.READ_EXTERNAL_STORAGE',
  'android.permission.READ_MEDIA_AUDIO',
  'android.permission.READ_MEDIA_IMAGES',
  'android.permission.READ_MEDIA_VIDEO',
  'android.permission.READ_SMS',
  'android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS',
  'android.permission.REQUEST_INSTALL_PACKAGES',
  'android.permission.SCHEDULE_EXACT_ALARM',
  'android.permission.SYSTEM_ALERT_WINDOW',
  'android.permission.WRITE_EXTERNAL_STORAGE',
  'android.permission.WRITE_SETTINGS',
};

const _foregroundPermissionByType = <String, String>{
  'camera': 'android.permission.FOREGROUND_SERVICE_CAMERA',
  'mediaProjection': 'android.permission.FOREGROUND_SERVICE_MEDIA_PROJECTION',
  'microphone': 'android.permission.FOREGROUND_SERVICE_MICROPHONE',
  'phoneCall': 'android.permission.FOREGROUND_SERVICE_PHONE_CALL',
};

void main(List<String> arguments) {
  if (arguments.length != 1) {
    stderr.writeln(
      'Usage: dart run tool/check_android_manifest.dart <merged-manifest.xml>',
    );
    exitCode = 64;
    return;
  }

  final manifest = File(arguments.single);
  if (!manifest.existsSync() ||
      manifest.statSync().type != FileSystemEntityType.file) {
    stderr.writeln('Merged Android manifest not found: ${manifest.path}');
    exitCode = 66;
    return;
  }

  final xml = manifest.readAsStringSync();
  final failures = <String>[];
  if (!xml.contains('package="com.vpsttt.webtui_chat"')) {
    failures.add('production package must be com.vpsttt.webtui_chat');
  }
  if (!xml.contains('android:targetSdkVersion="36"')) {
    failures.add('production manifest must target Android API 36');
  }
  if (!xml.contains('android:usesCleartextTraffic="false"')) {
    failures.add('production application must disable cleartext traffic');
  }
  if (!xml.contains('android:allowBackup="false"')) {
    failures.add('production application must disable Android backup');
  }

  final permissions = RegExp(
    r'<uses-permission\b[^>]*android:name="([^"]+)"[^>]*/?>',
    multiLine: true,
  ).allMatches(xml).map((match) => match.group(1)!).toSet();

  final forbidden = permissions.intersection(_forbiddenPermissions).toList()
    ..sort();
  for (final permission in forbidden) {
    failures.add('forbidden broad permission present: $permission');
  }

  final foregroundTypes = <String>{};
  for (final match in RegExp(
    r'android:foregroundServiceType="([^"]+)"',
  ).allMatches(xml)) {
    foregroundTypes.addAll(match.group(1)!.split('|'));
  }
  for (final type in foregroundTypes) {
    final permission = _foregroundPermissionByType[type];
    if (permission != null && !permissions.contains(permission)) {
      failures.add('$type foreground service is missing $permission');
    }
  }
  if (foregroundTypes.isNotEmpty &&
      !permissions.contains('android.permission.FOREGROUND_SERVICE')) {
    failures.add('foreground services require FOREGROUND_SERVICE permission');
  }

  final exportedComponent = RegExp(
    r'<(service|receiver|provider)\b([^>]*android:exported="true"[^>]*)>',
    multiLine: true,
  );
  for (final match in exportedComponent.allMatches(xml)) {
    final attributes = match.group(2)!;
    if (!attributes.contains('android:permission=')) {
      final name = RegExp(
        r'android:name="([^"]+)"',
      ).firstMatch(attributes)?.group(1);
      failures.add(
        'exported ${match.group(1)} lacks a protecting permission: '
        '${name ?? 'unknown component'}',
      );
    }
  }

  final customPermission = RegExp(
    r'<permission\b[^>]*android:name="com\.vpsttt\.webtui_chat\.PERMISSION_CALL"[^>]*>',
    multiLine: true,
  ).firstMatch(xml);
  if (permissions.contains('com.vpsttt.webtui_chat.PERMISSION_CALL') &&
      (customPermission == null ||
          !customPermission
              .group(0)!
              .contains('android:protectionLevel="signature"'))) {
    failures.add('custom call permission must use signature protection');
  }

  if (failures.isNotEmpty) {
    stderr.writeln('Merged Android manifest failed release policy:');
    for (final failure in failures) {
      stderr.writeln('- $failure');
    }
    exitCode = 1;
    return;
  }

  final sortedPermissions = permissions.toList()..sort();
  stdout.writeln(
    'Merged Android manifest validated: ${sortedPermissions.length} '
    'permissions, foreground types ${foregroundTypes.toList()..sort()}.',
  );
}

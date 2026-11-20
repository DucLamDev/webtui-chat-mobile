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

/// Quyền bộ nhớ kiểu cũ chỉ được khai khi giới hạn `android:maxSdkVersion`
/// tới mức ghi ở đây. Lưu ảnh / video vào thư viện máy (thư viện `gal`) cần
/// WRITE_EXTERNAL_STORAGE trên Android 9–10; từ Android 11 (API 30) quyền này
/// không còn tác dụng nên Google Play không coi là quyền truy cập rộng. Không
/// giới hạn hoặc giới hạn cao hơn vẫn bị chặn như mọi quyền trong
/// [_forbiddenPermissions].
const _legacyStoragePermissionMaxSdk = <String, int>{
  'android.permission.WRITE_EXTERNAL_STORAGE': 29,
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

  final report = checkAndroidManifestPolicy(manifest.readAsStringSync());
  if (report.failures.isNotEmpty) {
    stderr.writeln('Merged Android manifest failed release policy:');
    for (final failure in report.failures) {
      stderr.writeln('- $failure');
    }
    exitCode = 1;
    return;
  }

  final sortedPermissions = report.permissions.toList()..sort();
  stdout.writeln(
    'Merged Android manifest validated: ${sortedPermissions.length} '
    'permissions, foreground types ${report.foregroundTypes.toList()..sort()}.',
  );
}

/// Kết quả kiểm manifest Android đã gộp theo chính sách phát hành.
final class AndroidManifestPolicyReport {
  const AndroidManifestPolicyReport({
    required this.failures,
    required this.permissions,
    required this.foregroundTypes,
  });

  /// Các điều vi phạm (rỗng = đạt).
  final List<String> failures;
  final Set<String> permissions;
  final Set<String> foregroundTypes;
}

/// Kiểm nội dung [xml] của manifest đã gộp (bản phát hành prod).
AndroidManifestPolicyReport checkAndroidManifestPolicy(String xml) {
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

  final permissions = <String>{};
  final forbidden = <String>{};
  for (final match in RegExp(
    r'<uses-permission\b([^>]*)/?>',
    multiLine: true,
  ).allMatches(xml)) {
    final attributes = match.group(1)!;
    final name = RegExp(
      r'android:name="([^"]+)"',
    ).firstMatch(attributes)?.group(1);
    if (name == null) continue;
    permissions.add(name);
    if (!_forbiddenPermissions.contains(name)) continue;
    final legacyMaxSdk = _legacyStoragePermissionMaxSdk[name];
    final declaredMaxSdk = int.tryParse(
      RegExp(
            r'android:maxSdkVersion="(\d+)"',
          ).firstMatch(attributes)?.group(1) ??
          '',
    );
    if (legacyMaxSdk != null &&
        declaredMaxSdk != null &&
        declaredMaxSdk <= legacyMaxSdk) {
      continue;
    }
    forbidden.add(name);
  }
  for (final permission in forbidden.toList()..sort()) {
    final legacyMaxSdk = _legacyStoragePermissionMaxSdk[permission];
    failures.add(
      legacyMaxSdk == null
          ? 'forbidden broad permission present: $permission'
          : 'forbidden broad permission present: $permission '
                '(only allowed with android:maxSdkVersion <= $legacyMaxSdk)',
    );
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

  return AndroidManifestPolicyReport(
    failures: failures,
    permissions: permissions,
    foregroundTypes: foregroundTypes,
  );
}

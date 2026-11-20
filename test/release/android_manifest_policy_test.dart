import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/check_android_manifest.dart';

/// Manifest đã gộp tối thiểu đạt mọi điều kiện, kèm [permissions].
String _mergedManifest(String permissions) =>
    '''
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="com.vpsttt.webtui_chat">
    <uses-sdk android:minSdkVersion="24" android:targetSdkVersion="36" />
    <uses-permission android:name="android.permission.INTERNET" />
$permissions
    <application
        android:allowBackup="false"
        android:usesCleartextTraffic="false" />
</manifest>
''';

List<String> _broadPermissionFailures(String xml) => checkAndroidManifestPolicy(
  xml,
).failures.where((failure) => failure.contains('broad permission')).toList();

void main() {
  // CI phát hành mobile-v1.0.21 dừng ở bước kiểm manifest: app khai
  // WRITE_EXTERNAL_STORAGE (giới hạn Android 10) để lưu ảnh / video vào thư
  // viện máy, mà chính sách cũ cấm hẳn quyền này nên không ra được bản Android.
  group('chính sách quyền của manifest phát hành Android', () {
    test('quyền ghi bộ nhớ kiểu cũ giới hạn tới Android 10 thì đạt', () {
      final report = checkAndroidManifestPolicy(
        _mergedManifest('''
    <uses-permission
        android:name="android.permission.WRITE_EXTERNAL_STORAGE"
        android:maxSdkVersion="29" />'''),
      );
      expect(report.failures, isEmpty);
      expect(
        report.permissions,
        contains('android.permission.WRITE_EXTERNAL_STORAGE'),
      );
    });

    test('quyền ghi bộ nhớ không giới hạn hoặc giới hạn cao hơn vẫn bị chặn', () {
      for (final permission in const [
        '<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" />',
        '<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" '
            'android:maxSdkVersion="30" />',
      ]) {
        expect(
          _broadPermissionFailures(_mergedManifest(permission)),
          [
            'forbidden broad permission present: '
                'android.permission.WRITE_EXTERNAL_STORAGE '
                '(only allowed with android:maxSdkVersion <= 29)',
          ],
          reason: permission,
        );
      }
    });

    test('quyền đọc bộ nhớ / thư viện ảnh vẫn bị chặn dù có giới hạn', () {
      expect(
        _broadPermissionFailures(
          _mergedManifest(
            '<uses-permission '
            'android:name="android.permission.READ_EXTERNAL_STORAGE" '
            'android:maxSdkVersion="29" />\n'
            '<uses-permission '
            'android:name="android.permission.READ_MEDIA_IMAGES" />',
          ),
        ),
        [
          'forbidden broad permission present: '
              'android.permission.READ_EXTERNAL_STORAGE',
          'forbidden broad permission present: '
              'android.permission.READ_MEDIA_IMAGES',
        ],
      );
    });

    test('manifest của app chỉ khai quyền được phép', () {
      // Manifest nguồn thiếu package / targetSdk (Gradle điền lúc gộp) nên
      // chỉ lấy các quyền app khai (bỏ dòng `tools:node="remove"` dùng để gỡ
      // quyền thư viện kéo vào) đặt vào manifest đạt chuẩn rồi kiểm.
      final source = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
      final declared = RegExp(r'<uses-permission\b[^>]*>')
          .allMatches(source)
          .map((match) => match.group(0)!)
          .where((element) => !element.contains('tools:node="remove"'))
          .toList();
      expect(
        declared.where((element) => element.contains('WRITE_EXTERNAL_STORAGE')),
        hasLength(1),
      );
      expect(
        checkAndroidManifestPolicy(
          _mergedManifest(declared.join('\n')),
        ).failures,
        isEmpty,
      );
    });
  });
}

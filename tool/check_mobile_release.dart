import 'dart:io';

void main() {
  final checks = <_ReleaseCheck>[
    _ReleaseCheck(
      label: 'Workflow mobile release job',
      file: File('.github/workflows/mobile.yml'),
      mustContain: const [
        'android-release:',
        'flutter build appbundle --release',
        'flutter build apk --release',
        'mobile-release-manifest.json',
        'sha256sum',
        '--build-number',
        'MOBILE_FIREBASE_ANDROID_APP_ID',
        'MOBILE_FIREBASE_IOS_APP_ID',
        'MOBILE_PRIVACY_POLICY_URL',
        'zipalign',
        'xcodebuild -version',
        'xcrun --sdk iphoneos --show-sdk-version',
        "grep -Eq '^26\\.'",
        'download_url',
        'checksum_sha256',
      ],
    ),
    _ReleaseCheck(
      label: 'Current SQLite native assets',
      file: File('pubspec.yaml'),
      mustContain: const ['drift: ^2.34.3', 'sqlite3: ^3.5.0'],
      mustNotContain: const ['sqlite3_flutter_libs'],
    ),
    _ReleaseCheck(
      label: 'Android least-privilege release manifest',
      file: File('android/app/src/main/AndroidManifest.xml'),
      mustContain: const [
        'android:allowBackup="false"',
        'android:usesCleartextTraffic="false"',
        'android.permission.READ_MEDIA_IMAGES',
        'android.permission.READ_MEDIA_VIDEO',
        'android.permission.READ_MEDIA_AUDIO',
        'android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS',
        'tools:node="remove"',
        'android:protectionLevel="signature"',
        'android.hardware.camera',
        'android.hardware.camera.front',
        'android.hardware.microphone',
        'android.hardware.bluetooth',
        'android:required="false"',
        'com.google.firebase.messaging.default_notification_channel_id',
      ],
    ),
    _ReleaseCheck(
      label: 'Android notification channel',
      file: File(
        'android/app/src/main/kotlin/com/vpsttt/webtui_chat/WebTuiApplication.kt',
      ),
      mustContain: const [
        'MESSAGE_CHANNEL_ID = "webtui_messages"',
        'NotificationManager.IMPORTANCE_HIGH',
      ],
    ),
    _ReleaseCheck(
      label: 'iOS CocoaPods project',
      file: File('ios/Podfile'),
      mustContain: const [
        "platform :ios, '13.0'",
        'flutter_install_all_ios_pods',
        'flutter_additional_ios_build_settings',
      ],
    ),
    _ReleaseCheck(
      label: 'iOS permission descriptions and app name',
      file: File('ios/Runner/Info.plist'),
      mustContain: const [
        '<string>WebTui Chat</string>',
        '<key>NSFaceIDUsageDescription</key>',
        '<key>NSLocalNetworkUsageDescription</key>',
        '<string>audio</string>',
        '<string>voip</string>',
        '<string>remote-notification</string>',
      ],
    ),
    _ReleaseCheck(
      label: 'iOS production push entitlement',
      file: File('ios/Runner/Runner.entitlements'),
      mustContain: const ['<string>production</string>'],
    ),
    _ReleaseCheck(
      label: 'iOS development push entitlement',
      file: File('ios/Runner/RunnerDebug.entitlements'),
      mustContain: const ['<string>development</string>'],
    ),
    _ReleaseCheck(
      label: 'iOS app privacy manifest',
      file: File('ios/Runner/PrivacyInfo.xcprivacy'),
      mustContain: const [
        '<key>NSPrivacyTracking</key>',
        '<false/>',
        'NSPrivacyAccessedAPICategoryFileTimestamp',
        'C617.1',
        '3B52.1',
        'NSPrivacyAccessedAPICategorySystemBootTime',
        '35F9.1',
        'NSPrivacyAccessedAPICategoryUserDefaults',
        'CA92.1',
        'NSPrivacyCollectedDataTypePhoneNumber',
        'NSPrivacyCollectedDataTypeEmailsOrTextMessages',
        'NSPrivacyCollectedDataTypePhotosorVideos',
        'NSPrivacyCollectedDataTypeAudioData',
        'NSPrivacyCollectedDataTypeDeviceID',
      ],
    ),
    _ReleaseCheck(
      label: 'iOS privacy manifest target membership',
      file: File('ios/Runner.xcodeproj/project.pbxproj'),
      mustContain: const [
        'PrivacyInfo.xcprivacy in Resources',
        'path = PrivacyInfo.xcprivacy',
      ],
    ),
    _ReleaseCheck(
      label: 'In-app account deletion contract',
      file: File(
        'lib/features/auth/data/repositories/account_repository_impl.dart',
      ),
      mustContain: const [
        "'/api/v1/users/me'",
        "'confirmation': confirmation",
        "'ownership_successor_email': normalizedSuccessorEmail",
      ],
    ),
    _ReleaseCheck(
      label: 'In-app account deletion UI',
      file: File(
        'lib/features/settings/presentation/screens/privacy_sessions_screen.dart',
      ),
      mustContain: const [
        "title: 'Xóa tài khoản'",
        "hintText: 'DELETE'",
        "labelText: 'Email thành viên nhận quyền'",
        'WEBTUI_PRIVACY_POLICY_URL',
      ],
    ),
    _ReleaseCheck(
      label: 'Store-safe login provider visibility',
      file: File(
        'lib/features/auth/presentation/google_sign_in_visibility.dart',
      ),
      mustContain: const [
        'targetPlatform != TargetPlatform.iOS',
        'clientId.trim().isNotEmpty',
        'serverClientId.trim().isNotEmpty',
      ],
    ),
    _ReleaseCheck(
      label: 'Password recovery is not a dead action',
      file: File('lib/features/auth/presentation/screens/login_screen.dart'),
      mustContain: const [
        'Key(\'forgot_password_button\')',
        '_showPasswordRecoveryGuidance',
        'liên hệ quản trị viên',
      ],
      mustNotContain: const ['onPressed: state.isLoading ? null : () {},'],
    ),
    _ReleaseCheck(
      label: 'Android production package and signing',
      file: File('android/app/build.gradle.kts'),
      mustContain: const [
        'applicationId = "com.vpsttt.webtui_chat"',
        'signingConfigs',
        'ANDROID_KEYSTORE_PASSWORD',
        'ANDROID_KEY_ALIAS',
        'ANDROID_KEY_PASSWORD',
        'WEBTUI_ALLOW_UNSIGNED_RELEASE',
        'requestedReleaseTask',
      ],
      mustNotContain: const [
        'signingConfig = signingConfigs.getByName("debug")',
      ],
    ),
    _ReleaseCheck(
      label: 'Android secret ignore rules',
      file: File('.gitignore'),
      mustContain: const [
        '/android/key.properties',
        '/android/app/*.jks',
        '/android/app/*.keystore',
      ],
    ),
    _ReleaseCheck(
      label: 'Internal distribution doc',
      file: File('docs/android-internal-distribution.md'),
      mustContain: const ['app-prod-release.apk', 'app-prod-release.aab'],
    ),
    _ReleaseCheck(
      label: 'Release security checklist',
      file: File('docs/release-security-checklist.md'),
      mustContain: const ['No `.jks`', 'flutter analyze', 'SHA-256'],
    ),
    _ReleaseCheck(
      label: 'Android device matrix',
      file: File('docs/android-device-matrix.md'),
      mustContain: const ['TalkBack', 'reduced motion', 'signed APK'],
    ),
    _ReleaseCheck(
      label: 'Play Console readiness',
      file: File('docs/google-play-readiness.md'),
      mustContain: const [
        'target Android 16',
        'Data safety',
        'Internal testing',
      ],
    ),
    _ReleaseCheck(
      label: 'Privacy policy draft',
      file: File('docs/privacy-policy-draft.md'),
      mustContain: const ['Data We Process', 'User Controls', 'Contact'],
    ),
    _ReleaseCheck(
      label: 'Cross-store release readiness',
      file: File('docs/store-release-readiness.md'),
      mustContain: const [
        'Current Verdict',
        'Production Push Model For A Store Binary',
        'Google Play Console Checklist',
        'App Store Connect Checklist',
        'DELETE /api/v1/users/me',
      ],
    ),
    _ReleaseCheck(
      label: 'Download page plan',
      file: File('docs/download-page-spec.md'),
      mustContain: const [
        'chat.vpsttt.com/download/',
        'SHA-256',
        'mobile-release-manifest.json',
      ],
    ),
    _ReleaseCheck(
      label: 'Android direct download plan',
      file: File('docs/android-direct-download-plan.md'),
      mustContain: const [
        'Android Direct Download Plan',
        'signed Android APK',
        'chat.vpsttt.com/downloads/files/android/stable/',
      ],
    ),
    _ReleaseCheck(
      label: 'Download page HTML',
      file: File('../webtui-chat-portal/download/index.html'),
      mustContain: const [
        'Tải WebTui Chat cho Android',
        'android-chat-preview.png',
        'id="apkLink"',
        'id="checksumValue"',
        './privacy.html',
      ],
    ),
    _ReleaseCheck(
      label: 'Download page CSS',
      file: File('../webtui-chat-portal/download/styles.css'),
      mustContain: const ['.hero', '.phone-preview', '@media'],
    ),
    _ReleaseCheck(
      label: 'Download page JS',
      file: File('../webtui-chat-portal/download/app.js'),
      mustContain: const [
        'mobile-release-manifest.json',
        'checksum_sha256',
        'download_url',
      ],
    ),
    _ReleaseCheck(
      label: 'Download page preview asset',
      file: File(
        '../webtui-chat-portal/download/assets/android-chat-preview.png',
      ),
    ),
    _ReleaseCheck(
      label: 'Download page privacy stub',
      file: File('../webtui-chat-portal/download/privacy.html'),
      mustContain: const ['Chính sách quyền riêng tư', 'support@vpsttt.com'],
    ),
    _ReleaseCheck(
      label: 'Public account-deletion page',
      file: File('../webtui-chat-portal/download/account-deletion.html'),
      mustContain: const [
        '<h1>Xóa tài khoản WebTUI Chat</h1>',
        '<strong>DELETE</strong>',
        'support@vpsttt.com',
        'href="./privacy.html"',
      ],
    ),
    _ReleaseCheck(
      label: 'Download host manifest example',
      file: File(
        '../webtui-chat-portal/download/mobile-release-manifest.example.json',
      ),
      mustContain: const [
        'com.vpsttt.webtui_chat',
        'checksum_sha256',
        'download_url',
        'download.vpsttt.com/downloads/files/android/stable/app-prod-release.apk',
      ],
    ),
  ];

  final failures = <String>[];
  for (final check in checks) {
    failures.addAll(check.failures());
  }

  if (failures.isNotEmpty) {
    stderr.writeln('Mobile release readiness check failed:');
    for (final failure in failures) {
      stderr.writeln('- $failure');
    }
    exitCode = 1;
  }
}

final class _ReleaseCheck {
  const _ReleaseCheck({
    required this.label,
    required this.file,
    this.mustContain = const [],
    this.mustNotContain = const [],
  });

  final String label;
  final File file;
  final List<String> mustContain;
  final List<String> mustNotContain;

  List<String> failures() {
    if (!file.existsSync()) {
      return ['$label: missing ${file.path}'];
    }
    if (mustContain.isEmpty && mustNotContain.isEmpty) {
      return [];
    }
    final content = file.readAsStringSync();
    return [
      for (final needle in mustContain)
        if (!content.contains(needle)) '$label: ${file.path} missing "$needle"',
      for (final needle in mustNotContain)
        if (content.contains(needle))
          '$label: ${file.path} must not contain "$needle"',
    ];
  }
}

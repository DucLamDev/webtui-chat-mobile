import 'dart:io';

void main() {
  final checks = <_ReleaseCheck>[
    _ReleaseCheck(
      label: 'Workflow mobile release job',
      file: File('.github/workflows/mobile.yml'),
      mustContain: const [
        'android-release:',
        'workflow_dispatch:',
        'android-play-signing-bootstrap:',
        'confirm_play_signing_bootstrap:',
        'INTERNAL_ONLY_DO_NOT_PROMOTE',
        'check_production_config.dart --platform=android --play-signing-bootstrap',
        'app-prod-play-signing-bootstrap-INTERNAL-ONLY.aab',
        'retention-days: 7',
        'No Play upload action belongs here',
        'environment: production',
        'FLUTTER_VERSION: 3.44.9',
        'flutter-version: \${{ env.FLUTTER_VERSION }}',
        'flutter build appbundle --release',
        'flutter build apk --release',
        'sha256sum',
        'app-prod-release.aab.sha256',
        '--build-number',
        'FIREBASE_MESSAGING_SENDER_ID: "595077870179"',
        'FIREBASE_PROJECT_ID: webtui-chat',
        'FIREBASE_ANDROID_APP_ID: "1:595077870179:android:a6f4ff5cc14a0d1485be56"',
        'MOBILE_FIREBASE_IOS_APP_ID',
        'MOBILE_PRIVACY_POLICY_URL',
        'MOBILE_TERMS_URL',
        'MOBILE_TERMS_VERSION',
        'MOBILE_PRIVACY_VERSION',
        'MOBILE_ACCOUNT_DELETION_URL',
        'MOBILE_SUPPORT_URL',
        'MOBILE_REFERENCE_INSTANCE_URL',
        'MOBILE_API_BASE_URL',
        'WEBTUI_ANDROID_COMPILE_SDK: "36"',
        'WEBTUI_ANDROID_TARGET_SDK: "36"',
        'check_production_config.dart --platform=android',
        'check_production_config.dart --platform=ios',
        'check_public_release_endpoints.dart --platform=android',
        'check_public_release_endpoints.dart --platform=ios',
        'PLAY_APP_SIGNING_SHA256_FINGERPRINTS',
        'APPLE_TEAM_ID',
        'check_android_manifest.dart',
        'check_android_elf_alignment.dart',
        'jarsigner -verify',
        'apkanalyzer',
        'libapp\\.so\\.(sym|dbg)\$',
        'libflutter\\.so\\.(sym|dbg)\$',
        'GITHUB_RUN_ATTEMPT',
        'zipalign',
        'xcodebuild -version',
        'xcrun --sdk iphoneos --show-sdk-version',
        "grep -Eq '^26\\.'",
        'The upload-key APK is used only for checks inside this job',
        'exact Play app-signing certificate',
      ],
      exactOccurrences: const {
        'flutter pub get': 4,
        'flutter pub get --enforce-lockfile': 4,
      },
      mustNotContain: const [
        'files: release/*',
        'path: release/*',
        'softprops/action-gh-release@',
        'downloads/files/android/stable/app-prod-release.apk',
        'contents: write',
        'actions/checkout@v',
        'subosito/flutter-action@v',
        'actions/upload-artifact@v',
        'softprops/action-gh-release@v',
        '--no-pub',
      ],
    ),
    _ReleaseCheck(
      label: 'Production runtime configuration validator',
      file: File('tool/check_production_config.dart'),
      mustContain: const [
        'WEBTUI_API_BASE_URL',
        'WEBTUI_PRIVACY_POLICY_URL',
        'WEBTUI_TERMS_URL',
        'WEBTUI_ACCOUNT_DELETION_URL',
        'WEBTUI_SUPPORT_URL',
        'WEBTUI_TERMS_VERSION',
        'WEBTUI_PRIVACY_VERSION',
        'PLAY_APP_SIGNING_SHA256_FINGERPRINTS',
        'APPLE_TEAM_ID',
        'APPLE_BUNDLE_ID',
        'chat.vpsttt.com',
        'ANDROID_KEYSTORE_PATH',
        '--platform=android',
        '--platform=ios',
        '--play-signing-bootstrap',
        'Internal-only and must never be promoted',
      ],
    ),
    _ReleaseCheck(
      label: 'Merged Android manifest validator',
      file: File('tool/check_android_manifest.dart'),
      mustContain: const [
        'android.permission.QUERY_ALL_PACKAGES',
        'android.permission.MANAGE_EXTERNAL_STORAGE',
        'android.permission.REQUEST_INSTALL_PACKAGES',
        'android.permission.FOREGROUND_SERVICE_PHONE_CALL',
        'android.permission.FOREGROUND_SERVICE_MICROPHONE',
        'android.permission.FOREGROUND_SERVICE_CAMERA',
        'exported',
        'com.vpsttt.webtui_chat',
      ],
    ),
    _ReleaseCheck(
      label: 'Public store endpoint validator',
      file: File('tool/check_public_release_endpoints.dart'),
      mustContain: const [
        '/ready',
        'assetlinks.json',
        'com.vpsttt.webtui_chat',
        'apple-app-site-association',
        'PLAY_APP_SIGNING_SHA256_FINGERPRINTS',
        'APPLE_TEAM_ID',
        'WEBTUI_TERMS_VERSION',
        'WEBTUI_PRIVACY_VERSION',
        '/api/v1/auth/legal-documents',
        '/api/v1/discovery',
        '/.well-known/vpsttt-chat',
        'instance_id',
        'api_contract_version',
        'minimum_supported_mobile_version',
        'account_deletion',
        'legal_acceptance',
        'allowRedirects: false',
        'requireJsonContentType: true',
      ],
    ),
    _ReleaseCheck(
      label: 'Android native ELF alignment validator',
      file: File('tool/check_android_elf_alignment.dart'),
      mustContain: const [
        'llvm-objdump',
        'arm64-v8a',
        'x86_64',
        '16 KB ELF alignment',
      ],
    ),
    _ReleaseCheck(
      label: 'Current SQLite native assets',
      file: File('pubspec.yaml'),
      mustContain: const [
        "flutter: '>=3.44.9'",
        'drift: ^2.34.3',
        'sqlite3: ^3.5.0',
      ],
      mustNotContain: const ['sqlite3_flutter_libs', 'flutter_background'],
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
        'android:name="flutter_deeplinking_enabled"',
        'android:value="false"',
        'android:path="/conversations"',
        'android:pathPrefix="/conversations/"',
        'android:path="/notifications"',
      ],
      mustNotContain: const [
        'android:pathPrefix="/notifications"',
        'android.permission.FOREGROUND_SERVICE_MEDIA_PROJECTION',
        'android:foregroundServiceType="mediaProjection"',
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
      label: 'Android adaptive and themed launcher icon',
      file: File('android/app/src/main/res/mipmap-anydpi-v33/ic_launcher.xml'),
      mustContain: const [
        '<adaptive-icon',
        '@drawable/ic_launcher_foreground',
        '<monochrome',
        '@drawable/ic_launcher_monochrome',
      ],
    ),
    _ReleaseCheck(
      label: 'Android 12 production splash',
      file: File('android/app/src/main/res/values-v31/styles.xml'),
      mustContain: const [
        'android:windowSplashScreenBackground',
        'android:windowSplashScreenAnimatedIcon',
        '@color/launcher_background',
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
        '<string>WebTUI Chat</string>',
        '<key>FlutterDeepLinkingEnabled</key>',
        '<false/>',
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
      mustContain: const [
        '<string>production</string>',
        '<key>com.apple.developer.associated-domains</key>',
        '<string>applinks:chat.vpsttt.com</string>',
      ],
    ),
    _ReleaseCheck(
      label: 'iOS development push entitlement',
      file: File('ios/Runner/RunnerDebug.entitlements'),
      mustContain: const [
        '<string>development</string>',
        '<key>com.apple.developer.associated-domains</key>',
        '<string>applinks:chat.vpsttt.com</string>',
      ],
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
        'config.privacyPolicyUrl',
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
        'resolvedTargetSdk < 36',
        'ndk.debugSymbolLevel = "FULL"',
        'isDebuggable = false',
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
      label: 'Android local signing template',
      file: File('android/key.properties.example'),
      mustContain: const [
        'storeFile=app/upload-keystore.jks',
        'storePassword=REPLACE_WITH_SECRET',
        'keyAlias=upload',
        'keyPassword=REPLACE_WITH_SECRET',
      ],
    ),
    _ReleaseCheck(
      label: 'Internal distribution doc',
      file: File('docs/android-internal-distribution.md'),
      mustContain: const [
        'app-prod-release.apk',
        'app-prod-release.aab',
        'must not use `--no-pub`',
      ],
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
        'Android 16/API 36',
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
      label: 'Play Data Safety source of truth',
      file: File('store/google-play/data-safety.md'),
      mustContain: const [
        'Google Play Data Safety Source Of Truth',
        'Firebase Core and Firebase Cloud Messaging',
        'App-generated device ID',
        'Account management',
      ],
    ),
    _ReleaseCheck(
      label: 'Play app-content submission gate',
      file: File('store/google-play/app-content.md'),
      mustContain: const [
        'User-generated content',
        'Account creation',
        'Reviewer credentials',
        'pre-launch report',
      ],
    ),
    _ReleaseCheck(
      label: 'Vietnamese Play Store listing',
      file: File('store/google-play/listing-vi.md'),
      mustContain: const [
        'WebTUI Chat',
        'Nhắn tin, gọi và cộng tác',
        'báo cáo tin nhắn hoặc tài khoản',
        'store-assets/play/phone/',
      ],
    ),
    _ReleaseCheck(
      label: 'Play foreground service evidence',
      file: File('store/google-play/foreground-service-declaration.md'),
      mustContain: const [
        '`phoneCall`',
        '`microphone`, `camera`',
        'phoneCall` only',
        'runtime permission',
        'Full-Screen Intent',
      ],
      mustNotContain: const ['`mediaProjection`'],
    ),
    _ReleaseCheck(
      label: 'Store reviewer-access template',
      file: File('store/google-play/reviewer-access.template.md'),
      mustContain: const [
        'No OTP',
        'Safety review',
        'report content',
        'block user',
      ],
    ),
    _ReleaseCheck(
      label: 'App Store privacy source of truth',
      file: File('store/app-store/app-privacy.md'),
      mustContain: const [
        'App Store Privacy',
        'User content',
        'account deletion',
      ],
    ),
    _ReleaseCheck(
      label: 'Vietnamese App Store listing',
      file: File('store/app-store/listing-vi.md'),
      mustContain: const [
        'Cộng tác trên máy chủ riêng',
        'Review note summary',
        'report/block',
      ],
    ),
    _ReleaseCheck(
      label: 'Official Android Firebase identifiers',
      file: File('config/firebase-production.env.example'),
      mustContain: const [
        'MOBILE_FIREBASE_MESSAGING_SENDER_ID=595077870179',
        'MOBILE_FIREBASE_PROJECT_ID=webtui-chat',
        'MOBILE_FIREBASE_ANDROID_APP_ID=1:595077870179:android:a6f4ff5cc14a0d1485be56',
        'REPLACE_FROM_GOOGLE_SERVICES_JSON_CURRENT_KEY',
      ],
    ),
    _ReleaseCheck(
      label: 'Release credentials contract',
      file: File('docs/release-credentials.md'),
      mustContain: const [
        'ANDROID_KEYSTORE_BASE64',
        'android-play-signing-bootstrap',
        'INTERNAL_ONLY_DO_NOT_PROMOTE',
        '7-day',
        'MOBILE_REFERENCE_INSTANCE_URL',
        'MOBILE_TERMS_URL',
        'MOBILE_PRIVACY_VERSION',
        'Firebase service accounts',
        '16 KB alignment',
      ],
    ),
    _ReleaseCheck(
      label: 'Canonical self-hosted store release contract',
      file: File('docs/self-hosted-store-release.md'),
      mustContain: const [
        'one universal AAB',
        'android-play-signing-bootstrap',
        'INTERNAL_ONLY_DO_NOT_PROMOTE',
        'retention 7 ngày',
        'reference/reviewer instance',
        'MOBILE_REFERENCE_INSTANCE_URL',
        'publisher-controlled App Link',
        'ENABLE_IOS_ASSOCIATION=false',
        'Legal Policy Contract v1',
        'PUSH_RELAY_INSTANCE_ID',
        '/push-relay/v1/deliveries',
        'Data Safety',
        'App Access',
        'versionCode mới',
      ],
    ),
    _ReleaseCheck(
      label: 'Production store runbook',
      file: File('docs/production-store-runbook.md'),
      mustContain: const [
        'Release này phải deploy backend trước',
        'android-play-signing-bootstrap',
        'INTERNAL_ONLY_DO_NOT_PROMOTE',
        'retention 7 ngày',
        '000039_ugc_moderation_and_legal_acceptance',
        'app-prod-release.aab',
        'Play App Signing',
        'apple-app-site-association',
        'credential placeholder',
      ],
    ),
    _ReleaseCheck(
      label: 'Download page plan',
      file: File('docs/download-page-spec.md'),
      mustContain: const [
        'download.webtui.vn/download/',
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
        'download.webtui.vn/downloads/files/android/stable/',
      ],
    ),
  ];

  final failures = <String>[];
  for (final check in checks) {
    failures.addAll(check.failures());
  }
  failures.addAll(
    _playSigningBootstrapFailures(File('.github/workflows/mobile.yml')),
  );

  if (failures.isNotEmpty) {
    stderr.writeln('Mobile release readiness check failed:');
    for (final failure in failures) {
      stderr.writeln('- $failure');
    }
    exitCode = 1;
  }
}

List<String> _playSigningBootstrapFailures(File workflow) {
  if (!workflow.existsSync()) {
    return const [];
  }
  final content = workflow.readAsStringSync();
  const startMarker = '  android-play-signing-bootstrap:';
  const endMarker = '\n  ios-archive-check:';
  final start = content.indexOf(startMarker);
  if (start < 0) {
    return const [
      'Play signing bootstrap safety: bootstrap job segment is missing.',
    ];
  }
  final end = content.indexOf(endMarker, start);
  if (end < 0) {
    return const [
      'Play signing bootstrap safety: bootstrap job has no bounded end marker.',
    ];
  }
  final segment = content.substring(start, end);
  const required = <String>[
    'ANDROID_KEYSTORE_BASE64',
    'WEBTUI_ANDROID_TARGET_SDK: "36"',
    '--play-signing-bootstrap',
    'check_android_manifest.dart',
    'jarsigner -verify',
    'libapp\\.so\\.(sym|dbg)\$',
    'libflutter\\.so\\.(sym|dbg)\$',
    'check_android_elf_alignment.dart',
    'app-prod-play-signing-bootstrap-INTERNAL-ONLY.aab',
    'retention-days: 7',
  ];
  const forbidden = <String>[
    'PLAY_APP_SIGNING_SHA256_FINGERPRINTS',
    'check_public_release_endpoints.dart',
    'r0adkll/upload-google-play',
    'fastlane supply',
    'gradle-play-publisher',
    'publishProdReleaseBundle',
  ];
  return <String>[
    for (final needle in required)
      if (!segment.contains(needle))
        'Play signing bootstrap safety: job missing "$needle".',
    for (final needle in forbidden)
      if (segment.contains(needle))
        'Play signing bootstrap safety: job must not contain "$needle".',
  ];
}

final class _ReleaseCheck {
  const _ReleaseCheck({
    required this.label,
    required this.file,
    this.mustContain = const [],
    this.mustNotContain = const [],
    this.exactOccurrences = const {},
  });

  final String label;
  final File file;
  final List<String> mustContain;
  final List<String> mustNotContain;
  final Map<String, int> exactOccurrences;

  List<String> failures() {
    if (!file.existsSync()) {
      return ['$label: missing ${file.path}'];
    }
    if (mustContain.isEmpty &&
        mustNotContain.isEmpty &&
        exactOccurrences.isEmpty) {
      return [];
    }
    final content = file.readAsStringSync();
    return [
      for (final needle in mustContain)
        if (!content.contains(needle)) '$label: ${file.path} missing "$needle"',
      for (final needle in mustNotContain)
        if (content.contains(needle))
          '$label: ${file.path} must not contain "$needle"',
      for (final entry in exactOccurrences.entries)
        if (entry.key.allMatches(content).length != entry.value)
          '$label: ${file.path} must contain "${entry.key}" exactly '
              '${entry.value} times',
    ];
  }
}

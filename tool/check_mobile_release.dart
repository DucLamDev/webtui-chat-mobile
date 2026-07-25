import 'dart:io';

void main() {
  final checks = <_ReleaseCheck>[
    _ReleaseCheck(
      label: 'Workflow mobile release job',
      file: File('../../.github/workflows/mobile.yml'),
      mustContain: const [
        'android-release:',
        'flutter build appbundle --release',
        'flutter build apk --release',
        'mobile-release-manifest.json',
        'sha256sum',
        'download_url',
        'checksum_sha256',
      ],
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
      file: File('../../portal/download/index.html'),
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
      file: File('../../portal/download/styles.css'),
      mustContain: const ['.hero', '.phone-preview', '@media'],
    ),
    _ReleaseCheck(
      label: 'Download page JS',
      file: File('../../portal/download/app.js'),
      mustContain: const [
        'mobile-release-manifest.json',
        'checksum_sha256',
        'download_url',
      ],
    ),
    _ReleaseCheck(
      label: 'Download page preview asset',
      file: File('../../portal/download/assets/android-chat-preview.png'),
    ),
    _ReleaseCheck(
      label: 'Download page privacy stub',
      file: File('../../portal/download/privacy.html'),
      mustContain: const ['Chính sách riêng tư', 'support@vpsttt.com'],
    ),
    _ReleaseCheck(
      label: 'Download host manifest example',
      file: File('../../portal/download/mobile-release-manifest.example.json'),
      mustContain: const [
        'com.vpsttt.webtui_chat',
        'checksum_sha256',
        'download_url',
        'chat.vpsttt.com/downloads/files/android/stable/app-prod-release.apk',
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

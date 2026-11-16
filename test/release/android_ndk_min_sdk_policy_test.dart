import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  String source(String path) => File(path).readAsStringSync();

  // opus_flutter_android 3.x (giải mã ghi âm WebM / Ogg cho iPhone) tự dịch
  // libopus bằng ndkBuild, khai minSdkVersion 19 và không khai ndkVersion.
  group('opus_flutter_android dựng được và đạt căn lề 16 KB', () {
    test('minSdk 19 của thư viện không làm dừng bản dựng', () {
      final pubspec = source('pubspec.yaml');
      final properties = source('android/gradle.properties');
      final appGradle = source('android/app/build.gradle.kts');

      expect(pubspec, contains('opus_flutter:'));
      // NDK của Flutter chỉ nhận từ API 21: thiếu dòng này thì
      // `flutter build apk` dừng ở lỗi CXX1110 khi cấu hình thư viện.
      expect(properties, contains('android.ndk.suppressMinSdkVersionError=21'));
      // Chỉ an toàn khi chính app không hạ minSdk xuống dưới 21 (đang theo
      // mặc định của Flutter là 24).
      expect(appGradle, contains('minSdk = flutter.minSdkVersion'));
    });

    test('libopus dịch bằng NDK của app (NDK r28+ căn lề 16 KB)', () {
      final rootGradle = source('android/build.gradle.kts');

      // Không ép thì Gradle dùng NDK 27 mặc định: libopus.so căn lề 4 KB,
      // check_android_elf_alignment và Google Play (Android 15+) từ chối.
      expect(rootGradle, contains('if (name == "opus_flutter_android")'));
      expect(rootGradle, contains('.project(":app")'));
      expect(rootGradle, contains('ndkVersion = appNdkVersion'));
    });
  });
}

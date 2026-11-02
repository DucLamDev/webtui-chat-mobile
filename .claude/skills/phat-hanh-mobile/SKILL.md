---
name: phat-hanh-mobile
description: Phát hành và cấu hình build app webtui-chat-mobile — quy trình CI .github/workflows/mobile.yml (kiểm tra PR, tag mobile-vX.Y.Z, AAB Android, TestFlight iOS), --dart-define, flavor, ký số, mã native iOS (AppDelegate, CallKit, PushKit) / Android (foreground service cuộc gọi), plugin callkit sửa riêng trong third_party, và các công cụ kiểm tra bằng chuỗi cố định. Dùng khi sửa workflow CI, pubspec, mã trong ios/ hay android/, Podfile / Gradle, khi chuẩn bị phát hành bản mới, khi build Android / iOS hoặc TestFlight lỗi.
---

# Phát hành và build app mobile

Đường dẫn tính từ gốc repo `webtui-chat-mobile/`. Phát triển tính năng trong `lib/`: skill `phat-trien-mobile`.
Không in / commit khoá, keystore, chứng chỉ, profile, tệp Firebase (`.gitignore` đã chặn; giữ nguyên như vậy).

## Quy trình CI (`.github/workflows/mobile.yml`)

| Job | Chạy khi | Làm gì |
|---|---|---|
| `verify` | Mọi PR, push `main` / `master` | Java 17 → `pub get --enforce-lockfile` → `dart format` → `tool/check_architecture.dart` → `tool/check_mobile_release.dart` → `flutter analyze` → `flutter test` → build APK debug flavor dev. Không chạy integration test |
| `android-release` | Tag `mobile-v*` (environment `production`) | Kiểm cấu hình production + endpoint công khai, build AAB + APK prod (`WEBTUI_RELEASE_CHANNEL=stable`), số phiên bản lấy từ tag, build number `RUN_NUMBER*100+ATTEMPT`, căn 16 KB, ký, kiểm manifest / symbols / ELF. Chỉ tải AAB lên artifact; **không** tự đẩy lên Play |
| `android-play-signing-bootstrap` | Chạy tay, gõ `INTERNAL_ONLY_DO_NOT_PROMOTE` | AAB dùng một lần cho Internal testing |
| `ios-archive-check` | Tag + `vars.ENABLE_IOS_RELEASE_CHECK == 'true'` | Build iOS không ký (Xcode 26) |
| `ios-release` | Tag + `vars.ENABLE_IOS_RELEASE == 'true'` | Nhập chứng chỉ vào keychain tạm, sinh `Signing.xcconfig` + `ExportOptions.plist`, `flutter build ipa`, fastlane `upload_testflight`; `IOS_SUBMIT_FOR_REVIEW` thì gửi duyệt (`ios/fastlane/Fastfile`) |

- Action ghim theo SHA kèm chú thích phiên bản (`uses: x@<sha> # vN`). **Không** dùng `@vN`.
- Secret / biến chỉ có trong environment `production` của GitHub. Danh sách và cách tạo: `docs/release-credentials.md`,
  `docs/ios-testflight-release.md` (hướng dẫn tiếng Việt, làm được trên Linux).

## Phát hành một bản

1. Các PR đã gộp vào `master`, CI xanh. `VERSION` + `CHANGELOG.md` đã có mục cho bản này.
2. Đọc `docs/production-store-runbook.md` (thứ tự bắt buộc: định danh → portal → backend → build → track).
   Máy chủ phải trả discovery hợp lệ cho bản app mới (`minimum_supported_mobile_version` ≤ bản này).
3. Tag `mobile-vX.Y.Z` trên commit cần phát hành. Gắn tag và đẩy tag là **phát hành thật**: hỏi người dùng trước, không
   tự làm.
4. `pubspec.yaml` vẫn ghi `version: 1.0.0+1` và không đồng bộ với `VERSION`; số thật lấy từ tag (`--build-name`,
   `--build-number`). Đừng "sửa cho khớp" nếu không được nhờ.

## Công cụ kiểm tra bằng chuỗi cố định

Sửa workflow, pubspec, docs phát hành có thể làm CI đỏ dù mã đúng. Chạy `dart run tool/check_mobile_release.dart` sau mỗi lần sửa.

- `tool/check_mobile_release.dart`: `mobile.yml` phải có **đúng 5** lần `flutter pub get --enforce-lockfile` và nhiều chuỗi
  cụ thể; cấm `--no-pub`, cấm action theo `@v`; pubspec cấm `flutter_background`, `sqlite3_flutter_libs`; một số docs
  (`docs/release-credentials.md`, `docs/self-hosted-store-release.md`...) phải chứa các cụm từ nhất định.
- `test/release/android_call_fgs_policy_test.dart`: pubspec phải dùng `path: third_party/flutter_callkit_incoming`, không
  `flutter_background`, không chia sẻ màn hình.
- Các `tool/check_production_config.dart`, `check_public_release_endpoints.dart`, `check_android_manifest.dart`,
  `check_android_elf_alignment.dart` chạy trong job phát hành.
- Đỏ: đọc tool / test xem đòi chuỗi gì, sửa đúng chỗ đó; không nới tool hay test cho qua.

## Build và `--dart-define`

```bash
flutter build apk --debug --flavor dev -t lib/main_dev.dart
flutter build appbundle --release --flavor prod -t lib/main_prod.dart --build-name X.Y.Z --build-number N
flutter build ipa --release -t lib/main_prod.dart --export-options-plist ios/ExportOptions.plist   # iOS không có flavor
```

- **Không bao giờ build release với `--no-pub`**: plugin chỉ dùng khi dev (`integration_test`) có thể lọt vào bản phát hành
  (`docs/android-internal-distribution.md`).
- `--dart-define` (đọc ở `lib/app/flavor/app_config.dart`, `app_flavor.dart`,
  `lib/core/notifications/firebase_runtime_options.dart`):
  - Máy chủ: `WEBTUI_API_BASE_URL`, `WEBTUI_WS_BASE_URL` (mặc định `https://chat.vpsttt.com`, WS tự suy ra `wss://host/ws`).
  - Phiên bản: `WEBTUI_APP_VERSION` (so với `minimum_supported_mobile_version` của máy chủ), `WEBTUI_RELEASE_CHANNEL`
    (dev → `internal`, staging → `beta`, prod → `stable`), `WEBTUI_RELEASE_SERVICE_URL` (mặc định `https://download.webtui.vn`, bắt buộc HTTPS).
  - Pháp lý: `WEBTUI_TERMS_URL`, `WEBTUI_PRIVACY_POLICY_URL`, `WEBTUI_TERMS_VERSION`, `WEBTUI_PRIVACY_VERSION`.
  - Firebase (thiếu thì app chạy không có push): `FIREBASE_API_KEY`, `FIREBASE_MESSAGING_SENDER_ID`,
    `FIREBASE_PROJECT_ID`, `FIREBASE_ANDROID_APP_ID`, `FIREBASE_IOS_APP_ID`, cùng vài biến tuỳ chọn.
  - `APP_FLAVOR` chỉ dùng với `lib/main.dart`; các flavor có `lib/main_{dev,staging,prod}.dart`.

## Android (`android/`)

- `applicationId` `com.vpsttt.webtui_chat`; flavor `dev` (`.dev`), `staging` (`.staging`), `prod`. `minSdk` theo Flutter,
  `targetSdk` ≥ 36 với bản release (Gradle báo lỗi nếu thấp hơn). Gradle cần **Java 17** (Java mới hơn làm hỏng build).
- Ký: biến môi trường `ANDROID_KEYSTORE_PATH`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`
  hoặc `android/key.properties` (đã gitignore). Release không ký sẽ lỗi, trừ khi `-PWEBTUI_ALLOW_UNSIGNED_RELEASE=true`.
- Cuộc gọi trên Android 14+: foreground service lần đầu chỉ là `phoneCall`, chỉ nâng lên micro / camera sau khi người dùng
  cấp quyền; không có `mediaProjection`. Kiểm tay theo `docs/android-api34-call-validation.md`.

## iOS (`ios/`)

- Bundle `com.vpsttt.webtuiChat`, chỉ có scheme Runner (không flavor). **Tối thiểu iOS 15.0** (Podfile + project) vì
  firebase_messaging bản mới yêu cầu.
- Background modes `audio`, `voip`, `remote-notification`; associated domain `applinks:chat.vpsttt.com`; URL scheme `webtui`.
- `ios/Runner/AppDelegate.swift`: PushKit VoIP → CallKit; khi CallKit bật âm thanh (`didActivateAudioSession`) phải báo cho
  `RTCAudioSession`, thiếu là gọi được mà không có tiếng.
  - Không viết closure kiểu trailing closure trong điều kiện `guard` (lỗi biên dịch Swift, đã sửa ở commit `025c3a3`).
  - `flutter_callkit_incoming.Data(args:)` cần `[String: Any?]`: đổi khoá `AnyHashable` sang `String` trước khi truyền
    (commit `7090aaf`).
- `ios/Flutter/Release.xcconfig` có `#include? "Signing.xcconfig"`: tệp này do CI sinh, không commit.
- Máy Linux không build được iOS: sửa Swift thì kiểm bằng job `ios-archive-check` (bật biến) hoặc nhờ người có máy Mac.

## Plugin callkit sửa riêng (`third_party/flutter_callkit_incoming`)

Bản 3.1.3 sửa thành `3.1.3+webtui.1`, lý do ghi trong `third_party/flutter_callkit_incoming/WEBTUI_PATCH.md`:
foreground service an toàn trên Android 14+, hàng đợi thao tác bền khi app đã tắt (WorkManager), nhận thao tác từ
Telecom / Bluetooth / đồng hồ. Nâng bản gốc thì phải chép lại các sửa đổi này và chạy lại test `test/release/`.

## MethodChannel native

`webtui/deeplink`, `webtui/biometric`, `webtui/privacy`, `webtui/launcher`; riêng iOS thêm `webtui/instance_binding`.
Đổi tên / tham số kênh phải sửa cả Dart lẫn Kotlin / Swift.

# WebTui Chat Mobile

Flutter mobile app nằm trong `clients/mobile/` của monorepo (hoặc `mobile/` khi
tách repository clients) và đi theo feature-first Clean Architecture:

```text
Presentation -> Application -> Domain <- Data
```

## Phase M1 Foundation

- `lib/app`: bootstrap, flavor config, router và root app.
- `lib/core`: Result/Failure, error mapper, request ID, Dio boundary, OpenAPI boundary, Drift database foundation, secure storage abstraction và logger redaction.
- `lib/design_system`: token màu, typography, spacing, radius, shadow, list density, bottom tab và segmented control theo reference Zalo-like/WebTui.
- `lib/features/<feature>`: mỗi feature tự chia `domain`, `application`, `data`, `presentation` khi bắt đầu có nghiệp vụ.

## Phase M2 Auth/Session

- `features/auth/domain`: entity và repository interface thuần Dart, không biết Dio, Flutter secure storage, Drift hay DTO.
- `features/auth/application`: login, refresh, logout, session revoke/list và app-lock PIN use case.
- `features/auth/data`: remote datasource, DTO mapper, repository implementation, token source và interceptor refresh.
- `features/auth/presentation`: login controller/screen; widget chỉ gọi controller/use case.

Token policy:

- Access token chỉ nằm trong memory của `SecureAuthTokenRepository`.
- Refresh token lưu qua `SecureKeyValueStore`, tương ứng Keychain/Keystore khi chạy mobile.
- Login/refresh/logout dùng `authDioProvider` không gắn auth interceptor; request nghiệp vụ dùng `dioProvider` có `AuthRefreshInterceptor`.
- Nhiều request 401 đồng thời đi qua `RefreshAccessTokenUseCase` single-flight, chỉ gọi `/auth/refresh` một lần.
- Logout luôn clear access token, refresh token, active workspace id và các key-value scope `session`/`workspace:*`.
- Device identity là UUID ngẫu nhiên do app tạo và lưu secure; không đọc hardware identifier nhạy cảm.

App lock/privacy:

- PIN app-lock lưu hash SHA-256 có salt theo device id trong secure storage.
- Biometric adapter sẽ gắn khi UX/backend có contract rõ; M2 đặt sẵn boundary use case/repository cho app lock.
- `PrivacyGuard` phủ nội dung khi app inactive/paused; Android `MainActivity` bật `FLAG_SECURE` qua MethodChannel `webtui/privacy`.

## Phase M3 Workspace/RBAC/Profile/Settings

- `features/workspace`: gọi API thật `GET /api/v1/workspaces` và `GET /api/v1/rbac/me?workspace_id=...`; UI gate bằng permission code qua `PermissionSet`, không suy từ tên role.
- Active workspace lưu trong secure store bằng `SecureStoreKey.activeWorkspaceId`.
- Khi đổi workspace, app reset runtime scope trong Drift (`workspace_runtime`, `workspace:{id}:runtime`) và tăng generation để rebuild shell/provider phụ thuộc workspace; route chọn workspace dùng `context.go('/')` để reset navigation stack.
- `features/profile`: gọi `GET|PATCH /api/v1/users/me`; avatar chọn bằng camera/gallery qua `image_picker`, upload multipart vào `POST /api/v1/workspaces/{workspace_id}/files`, rồi cập nhật `avatar_url`.
- `features/settings`: lưu theme/language/notification/privacy preview theo session scope local; màn quyền riêng tư dùng session API từ M2 để list/revoke phiên.
- 403 từ backend được giữ message tiếng Việt trong `FailureKind.forbidden` và hiển thị như lỗi quyền, không map thành lỗi hệ thống chung.

## Flavor Và Base URL

Android có 3 product flavors: `dev`, `staging`, `prod`. Dart entrypoint tương ứng:

```sh
flutter run --flavor dev -t lib/main_dev.dart
flutter run --flavor staging -t lib/main_staging.dart
flutter run --flavor prod -t lib/main_prod.dart
```

Base URL không nằm trong widget. Cấu hình mặc định của cả 3 flavor đều trỏ backend thật `https://chat.vpsttt.com` để các chức năng sử dụng được ngay. Khi cần test backend local, có thể override bằng:

```sh
flutter run --flavor dev -t lib/main_dev.dart --dart-define=WEBTUI_API_BASE_URL=http://10.0.2.2:8080
```

## Google Sign-In

Nút Google lấy ID token bằng plugin `google_sign_in`, sau đó gửi token tới backend qua `POST /api/v1/auth/google`. Cấu hình OAuth client bằng `--dart-define`:

```sh
flutter run --flavor prod -t lib/main_prod.dart \
  --dart-define=GOOGLE_OAUTH_CLIENT_ID=your-platform-client-id.apps.googleusercontent.com \
  --dart-define=GOOGLE_OAUTH_SERVER_CLIENT_ID=your-web-client-id.apps.googleusercontent.com
```

`GOOGLE_OAUTH_SERVER_CLIENT_ID` phải trùng với `GOOGLE_CLIENT_ID` trên backend để backend xác minh đúng audience của ID token. Android vẫn cần khai báo package name và SHA-1/SHA-256 của app trong Google Cloud/Firebase Console.

## Kết Nối API Mobile

Flutter chạy native trên Android/iOS không bị chính sách CORS của trình duyệt. Khi app báo không thể kết nối máy chủ, kiểm tra DNS, chứng chỉ HTTPS, firewall và Nginx trước. Base URL production hiện là `https://chat.vpsttt.com`.

```sh
curl -I https://chat.vpsttt.com/ready
sudo ss -lntp | grep -E ':80|:443'
docker compose --env-file .compose.env -f deploy/docker/compose.prod.yml ps
docker compose --env-file .compose.env -f deploy/docker/compose.prod.yml logs --tail=100 nginx
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
```

## Firebase Push Notification

Mobile đăng ký thiết bị với backend qua `POST /api/v1/mobile/devices`. Nếu Firebase đã được cấu hình, app sẽ lấy FCM token và gửi lên backend; nếu chưa có cấu hình Firebase, app vẫn chạy và chỉ đăng ký thiết bị với `push_provider=none`.

Có thể cấu hình Firebase bằng native config của FlutterFire, hoặc truyền nhanh bằng `--dart-define`:

```sh
flutter run --flavor prod -t lib/main_prod.dart \
  --dart-define=FIREBASE_PROJECT_ID=your-project-id \
  --dart-define=FIREBASE_MESSAGING_SENDER_ID=123456789 \
  --dart-define=FIREBASE_API_KEY=AIza... \
  --dart-define=FIREBASE_ANDROID_APP_ID=1:123456789:android:abc
```

Với iOS, dùng `FIREBASE_IOS_APP_ID` và có thể bổ sung `FIREBASE_IOS_BUNDLE_ID` nếu cần.

## Ranh Giới Phụ Thuộc

- Presentation chỉ gọi controller/use case và design system.
- Dio, Drift, secure storage, Firebase và generated DTO/OpenAPI client không được import trong presentation/widget.
- Repository interface đặt trong domain; implementation nằm trong data.
- Access token giữ trong memory; refresh token đi qua `SecureKeyValueStore`.
- Cache/local data luôn phải có scope tenant như `workspace_id` khi thêm bảng nghiệp vụ.

Chạy rule kiến trúc:

```sh
dart run tool/check_architecture.dart
```

## Lệnh Kiểm Tra

```sh
flutter pub get
dart format --set-exit-if-changed lib test integration_test tool
dart run tool/check_architecture.dart
dart run tool/check_mobile_release.dart
flutter analyze
flutter test
flutter test integration_test
flutter build apk --debug --flavor dev -t lib/main_dev.dart
```

## Android Packaging M11

- Workflow `.github/workflows/mobile.yml` chay format, architecture check, analyze, unit/widget test, integration smoke test va debug APK.
- Job release chi build signed AAB/APK khi co du secret `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`.
- Release artifact co APK, AAB, SHA-256 checksum va `mobile-release-manifest.json`.
- Lenh `flutter test integration_test` can Android emulator/device; GitHub Actions chay qua Android emulator.
- Huong dan van hanh: `docs/android-internal-distribution.md`.
- Checklist security/privacy: `docs/release-security-checklist.md`.
- Device matrix M10/M11: `docs/android-device-matrix.md`.
- Play Console readiness: `docs/google-play-readiness.md`.
- Privacy policy draft: `docs/privacy-policy-draft.md`.
- Android direct download plan: `docs/android-direct-download-plan.md`.
- Static download page source: `../../portal/download/index.html`.

## Reference UI

Ảnh reference của monorepo nằm tại
`../docs/design/mobile/references/webtui-mobile-zalo-reference.png`. Phase M1
dựng shell và design tokens; Phase M2 thêm auth/session foundation và login
entrypoint, chưa phụ thuộc backend/mock production trong widget test.

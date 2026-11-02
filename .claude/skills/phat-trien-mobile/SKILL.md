---
name: phat-trien-mobile
description: Cách làm việc với app Flutter webtui-chat-mobile — kiến trúc lib/ (feature + Clean Architecture, Riverpod viết tay, Dio, Result), thêm màn hình / tính năng từ datasource tới giao diện, gọi API và WebSocket, lưu cục bộ theo instance, chữ tiếng Việt, design system, test bằng fake viết tay, lệnh kiểm tra như CI và các bẫy. Dùng khi sửa hoặc thêm mã trong lib/ hay test/, sửa lỗi màn hình chat / hộp thư / gọi điện / thông báo, hoặc khi người dùng hỏi app chạy thế nào.
---

# Phát triển app mobile (Flutter)

Đường dẫn tính từ gốc repo `webtui-chat-mobile/`. Phát hành, CI, mã native iOS / Android: xem skill `phat-hanh-mobile`.

**Repo công khai (mã nguồn mở).** Không commit: địa chỉ máy chủ nội bộ, khoá, tệp Firebase, tài khoản thử, tài liệu
hay đường dẫn mã của backend (backend là repo riêng, không công khai). Tính năng chỉ dành cho một máy chủ phải bật theo
discovery, không theo cờ cứng.

## Sản phẩm trong app

- Một bản build dùng cho mọi máy chủ tự host: người dùng nhập domain → `GET /api/v1/discovery?domain=` → đăng nhập
  (mật khẩu, mã mời, OIDC qua `webtui://oidc`). Khởi động: `lib/app/bootstrap.dart`; gốc widget `lib/app/app.dart` bọc
  `MobileUpdateGate` → `PrivacyGuard` → `AppLockGate` → `LegalAcceptanceGate` → router.
- Route (`lib/app/router/app_router.dart`, go_router): `/login`, `/` (4 tab: **Tin nhắn**, **Bạn bè**, **Công việc**,
  **Cài đặt**; `?tab=contacts|tools|settings`), `/conversations/:channel_id`, `/channels/new`, `/channels/:id`,
  `/notifications`, `/profile`, `/settings`, `/privacy`, `/feedback`.
- Hộp thư (`features/conversations/presentation/controllers/conversation_home_controller.dart`): DM + nhóm / kênh gộp
  chung, ghim lên đầu; lọc `all, unread, direct, group, favorite, bot`. Tab "Nghiệp vụ" (lọc `bot`) và dải truy cập nhanh
  chỉ hiện khi `discovery.automationEnabled` (máy chủ `chat.vpsttt.com`, zone `vpsttt_internal`, có capability `automation`).
- Tab Công việc (`workspace_tools_screen.dart`): họp nhóm, đã chia sẻ, ghi chú chung, bảng trắng, việc cần làm.
- Gọi điện: `webrtc_call_screen.dart` (`flutter_webrtc`), phiên gọi qua REST `/calls`, tín hiệu qua WebSocket + REST
  `/signals`; cuộc gọi đến qua `flutter_callkit_incoming` (bản sửa riêng trong `third_party/`), iOS có PushKit VoIP.
- Phần `business` (ticket, flow bot, cronjob, API token) có đủ các lớp nhưng chưa có route mở `BusinessDashboardScreen`;
  `WorkspaceSelectorScreen` cũng chưa được route (`/workspaces` chuyển về `/`). Hỏi người dùng trước khi xoá hay nối lại.

## Kiến trúc `lib/`

- `lib/app` (bootstrap, flavor, router, providers) · `lib/core` (network, error, result, database, security,
  notifications, platform, privacy) · `lib/design_system` (token + component `WebTui*`) ·
  `lib/features/<f>/{domain,application,data,presentation}`.
- Chiều phụ thuộc: presentation → application (use case) → domain ← data. Presentation **không** gọi `ApiTransport`,
  Dio, Drift, secure storage, Firebase trực tiếp (`tool/check_architecture.dart` chặn một phần; hai chỗ cũ
  `feedback_screen.dart`, `webrtc_call_screen.dart` gọi `apiTransportProvider` thẳng — đừng bắt chước).
- **Riverpod 2 viết tay, không codegen.** Controller: `StateNotifier` + `StateNotifierProvider.autoDispose.family<..., String>`
  theo `workspaceId`. **Mọi** repository / use case nối ở một tệp: `lib/app/providers/foundation_providers.dart`.
- Không freezed / json_serializable: model là `final class` + `copyWith` viết tay.
- Mạng (Dio 5): datasource chỉ phụ thuộc `ApiTransport` (`core/network/api_transport.dart`). `dioProvider` có
  interceptor request-id, tự refresh token (401 → refresh một lần rồi gọi lại), chấp nhận điều khoản (409
  `LEGAL_ACCEPTANCE_REQUIRED`), log đã che dữ liệu nhạy cảm. `authDioProvider` cho đăng nhập / refresh.
- Đọc JSON bằng `core/network/api_response.dart`: `envelopeItem`, `envelopeList` (tự bóc `{data: ...}`),
  `stringField(map, ['snake', 'camel'])`, `intField`, `boolField`, `dateTimeField`. Encode id trong path bằng `Uri.encodeComponent`.
- Lỗi: repository bọc `guardResult(() => remote.x())` → `Result<T>` (`Success` / `FailureResult`);
  `core/error/error_mapper.dart` đổi mã HTTP sang `FailureKind`, lấy `error.message` của máy chủ. Câu toàn ASCII bị thay
  bằng câu chung tiếng Việt.
- Realtime: `features/conversations/data/repositories/web_socket_conversation_realtime_repository.dart` (`dart:io`
  WebSocket, token ở header, ping 25 giây, mất kết nối sau 70 giây; `type` lạ bị bỏ qua).
- Lưu cục bộ: Drift chỉ có **một bảng key-value** (`core/database/app_database.dart`); mọi khoá phải theo instance
  (`InstanceScope.storagePrefix`) và workspace. Provider phụ thuộc `activeInstanceScopeProvider` ném lỗi khi chưa có
  discovery. Bí mật qua `SecureKeyValueStore` + enum `SecureStoreKey`.

## Thêm một tính năng (mẫu chuẩn: `features/moderation`)

1. `domain/entities/<f>.dart` (entity, enum có `apiValue`) · `domain/repositories/<f>_repository.dart` (interface trả `Future<Result<T>>`).
2. `data/datasources/<f>_remote_data_source.dart` (gọi `ApiTransport`, đọc JSON có dự phòng) ·
   `data/repositories/<f>_repository_impl.dart` (`guardResult`).
3. `application/use_cases/<f>_use_cases.dart`: mỗi use case một class có `execute()`, kiểm đầu vào, trả
   `Failure(kind: validation, message: '<tiếng Việt có dấu>', code: 'UPPER_SNAKE')`.
4. Nối provider trong `foundation_providers.dart` (thêm import + provider cạnh nhóm cùng loại).
5. `presentation/controllers/<f>_controller.dart` (có factory `@visibleForTesting forTesting`) + widget / màn hình;
   màn hình mới thêm `GoRoute` trong `app_router.dart`. Có tải dữ liệu thì đủ trạng thái đang tải / rỗng / lỗi / không quyền.
6. Test trong `test/features/<f>/{application,data,presentation}/`.
7. `VERSION` + một mục đầu `CHANGELOG.md` (mẫu trong chính tệp đó).

Endpoint chưa có trên máy chủ: dừng lại báo người dùng (cần làm phía backend trước). Không tự đoán định dạng JSON mới.

## Chữ và giao diện

- Locale cố định `vi`, không có ARB: chữ viết thẳng trong mã, **tiếng Việt có dấu**. `test/global/vietnamese_diacritics_rule_test.dart`
  quét `lib/` bắt chữ không dấu ("khong", "chua"...).
- Design system kiểu Zalo: token `lib/design_system/tokens/*` (màu chính `0xFF0877F2`, font `WebTuiRoboto`), component
  `WebTui*`; mẫu `docs/design/mobile/references/mobile-ui-reference.md`.
- Ảnh / video từ mạng chỉ qua `WebTuiOwnedDecodedImage` / `WebTuiAvatar`; **cấm** `Image.network`, `Image.memory`,
  `VideoPlayerController.networkUrl` (`test/release/media_network_policy_test.dart`).

## Lệnh kiểm tra (giống job `verify` của CI)

```bash
flutter pub get --enforce-lockfile
dart format --set-exit-if-changed lib test integration_test tool
dart run tool/check_architecture.dart
dart run tool/check_mobile_release.dart
flutter analyze
flutter test
flutter run --flavor dev -t lib/main_dev.dart --dart-define=WEBTUI_API_BASE_URL=<máy chủ thử>
```

- Flutter đúng bản `FLUTTER_VERSION` trong `.github/workflows/mobile.yml`.
- Test: **không mockito / mocktail**. Fake viết tay `final class _FakeXRepository implements XRepository`,
  `_RecordingApiTransport implements ApiTransport` (ghi path / method / body để kiểm), widget test dùng
  `ProviderScope(overrides: [xProvider.overrideWithValue(fake)])`, DB test dùng `createInMemoryDriftConnection()`.
- `flutter test` **ghi đè** `test/screenshots/phase_m4_*.png`: không commit các ảnh này nếu không cố ý đổi giao diện
  (`git checkout -- test/screenshots` để bỏ).
- `test/release/*.dart`, `tool/check_*.dart` kiểm **chuỗi cố định** trong mã, pubspec, workflow, docs: đỏ thì đọc test
  xem nó đòi gì, sửa đúng chỗ, không nới test.
- `integration_test/app_smoke_test.dart` đã cũ (chữ hỏng mã hoá, còn chờ màn đăng nhập) và CI không chạy nó.

## Tài liệu lệch với mã (tin mã)

- README nói access token chỉ ở bộ nhớ: chế độ `durable` có lưu vào secure storage (`secure_auth_token_repository.dart`).
- README nói CI chạy integration test trên emulator: không có.
- README nói ảnh đại diện tải qua `/workspaces/{id}/files`: mã dùng `POST /api/v1/users/me/avatar`.
- `docs/planning/mobile-flutter-roadmap.md` đề xuất riverpod_generator, freezed, web_socket_channel, OpenAPI codegen:
  mã không dùng.

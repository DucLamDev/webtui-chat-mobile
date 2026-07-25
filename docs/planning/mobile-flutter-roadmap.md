# Kế hoạch triển khai Mobile App Flutter cho WebTui Chat

Tài liệu này chia việc triển khai Mobile App thành các phase và task có thể đưa thẳng vào backlog. Mục tiêu cuối là đạt đầy đủ chức năng người dùng trên Android và iOS, dùng API/WebSocket thật, hỗ trợ native push, camera, file, voice, deep link, offline và lifecycle nền; không mock nghiệp vụ trong bản phát hành.

## 1. Mục tiêu

- Cung cấp trải nghiệm mobile native, không nhúng WebView của web app.
- Dùng chung backend, OpenAPI contract, event schema và permission model với web/desktop.
- Có đầy đủ auth, workspace, chat, channel, direct message, media, notification, bot, automation, phòng ban và settings.
- Hoạt động tốt khi mạng yếu, app background/foreground, thiết bị bị kill và token push thay đổi.
- Bảo vệ refresh token bằng secure storage và dữ liệu cache bằng cơ chế phù hợp với dữ liệu nội bộ.
- Android phát hành trước, sau đó iOS qua TestFlight/App Store.

Admin Panel tiếp tục là web riêng. Mobile chỉ hiển thị chức năng người dùng được permission cho phép và có thể mở Admin Panel ngoài app cho quản trị viên.

## 2. Quan hệ với source Next.js hiện tại

Source web/admin hiện tại dùng Next.js `16.2.10` App Router và React `19.2.7`. Flutter không thay thế hoặc biên dịch lại source Next.js:

- Next.js tiếp tục phục vụ Web App và Admin Panel.
- Flutter là native client độc lập cho Android/iOS.
- Flutter không tái sử dụng React component, Next.js route hoặc Zustand/React Query.
- Phần dùng chung giữa Next.js và Flutter là Go backend, OpenAPI schema, DTO, permission code, quy ước error envelope và WebSocket event contract.
- Dart API client được sinh từ OpenAPI; không dịch thủ công TypeScript API client sang Dart.

Vì vậy roadmap Flutter dùng khái niệm parity với Next.js web, không phải chuyển đổi source Next.js sang Flutter.

## 3. Nguyên tắc bắt buộc

- Không viết URL API rải rác trong widget/repository; dùng Dart API client sinh từ OpenAPI hoặc wrapper thống nhất.
- Không sao chép TypeScript DTO thủ công nếu có thể sinh từ contract.
- Access token giữ trong memory; refresh token dùng `flutter_secure_storage`/Keychain/Keystore.
- Dữ liệu luôn scope theo `workspace_id`, `channel_id`, `user_id`.
- UI gate theo permission code, backend vẫn là lớp kiểm tra cuối.
- WebSocket chỉ phân phối event; REST/local database là nguồn để phục hồi trạng thái.
- Message retry phải có idempotency key.
- Push payload không chứa token/secret và tuân thủ tùy chọn ẩn preview.
- Không log nội dung message, Authorization header, refresh token hoặc URL có access token.
- Mọi phase phải chạy `flutter analyze`, unit/widget test và không thêm mock vào flavor production.

### 3.1. Clean Architecture bắt buộc

Mobile app phải đi theo hướng feature-first, mỗi feature tự chia layer rõ ràng. Dependency chỉ được chảy từ ngoài vào trong:

```text
Presentation -> Application -> Domain <- Data
```

| Lớp | Trách nhiệm | Được phép phụ thuộc | Không được phép | Deliverable bắt buộc |
|---|---|---|---|---|
| Domain | Entity, value object, repository contract, domain error, rule nghiệp vụ | Dart thuần, package rất nhẹ không dính Flutter | Flutter widget, Dio, Drift, Secure Storage, Firebase, JSON DTO | Entity bất biến, interface repository, use case input/output rõ |
| Application | Điều phối use case, transaction logic, permission decision, sync command | Domain, clock/id generator abstraction | Widget, API route cụ thể, SQL, plugin native trực tiếp | Use case độc lập test được bằng fake repository |
| Data | API client, DTO, mapper, local database, secure storage, repository implementation | Domain contract, generated OpenAPI client, Drift/Dio/plugin adapter | Gọi widget/state trực tiếp, trả DTO lên UI | Mapper DTO/entity, repository impl, data source test |
| Presentation | Screen, widget, state notifier, form validation UI, navigation | Application use case, UI model, design system | Gọi Dio/Drift/Secure Storage trực tiếp, chứa rule backend | Screen state có loading/empty/error/success và widget test |
| Infrastructure/Core | HTTP, websocket, database, crypto, notification, telemetry adapter | Abstraction được inject | Nghiệp vụ feature cụ thể | Adapter dùng chung, interceptor, redaction, lifecycle hook |

Quy tắc kiểm soát kiến trúc:

- DTO từ OpenAPI chỉ sống ở `data`; UI và domain không import DTO.
- Entity domain không có annotation của JSON/Drift/Firebase.
- Repository interface đặt ở domain, implementation đặt ở data.
- Use case là cửa vào duy nhất cho nghiệp vụ từ presentation.
- Riverpod provider ở presentation/application chỉ compose dependency, không chứa query SQL hoặc URL API.
- Mọi state mutation realtime/offline phải đi qua reducer/use case, tránh cập nhật list message rải rác trong widget.
- Mỗi feature có `README.md` ngắn ghi entity chính, use case, API, event realtime, permission code và test bắt buộc.

### 3.2. Multi-tenant, workspace và quyền quản trị

Sản phẩm là mô hình nhiều công ty, mỗi công ty là một workspace độc lập. Mobile phải tôn trọng tenant boundary như backend.

| Vai trò | Phạm vi | Mobile cần hiển thị | Không được làm |
|---|---|---|---|
| Super admin | Toàn hệ thống, nhiều workspace | Danh sách workspace, trạng thái workspace, nhảy vào workspace theo quyền, màn quản trị tối giản nếu được bật | Trộn dữ liệu chat giữa workspace, cache chung không có `workspace_id` |
| Workspace admin | Một workspace/công ty | Quản lý thành viên, kênh, bot, flow AI, ticket, automation theo permission | Nhìn thấy secret AI/API token dạng plaintext |
| Member/Agent | Workspace được mời | Chat, ticket, bot session, file, thông báo theo quyền | Thấy menu admin khi không có permission |
| Guest/External user | Phạm vi rất hẹp nếu có | Hội thoại/ticket được cấp quyền | Tự search user/channel ngoài phạm vi |

Quy tắc kỹ thuật:

- Mọi bảng local cache phải có `workspace_id` hoặc nằm trong secure/session store riêng.
- Khi đổi workspace phải reset provider scope, websocket subscription, unread counter, query cursor và navigation stack.
- Permission code phải lấy từ backend; mobile chỉ ẩn/hiện và chặn UX sớm, backend vẫn quyết định cuối cùng.
- Route deep link phải chứa đủ `workspaceSlug/workspaceId` để tránh mở nhầm tenant.

### 3.3. Bot/AI theo từng công ty, không hard-code flow VPSTTT

Mobile chỉ là client cấu hình và sử dụng bot; mobile không gọi thẳng OpenAI/LLM provider để tránh lộ key. Bot runtime nằm ở backend.

| Mảng | Yêu cầu thiết kế | Ghi chú Clean Architecture |
|---|---|---|
| Bot catalog | Workspace admin thấy danh sách bot của workspace, trạng thái bật/tắt, kênh được gắn bot | Domain entity `Bot`, `BotInstallation`, `BotStatus` |
| AI provider | Cấu hình provider/model qua backend: OpenAI-compatible, local gateway hoặc provider nội bộ | Mobile chỉ gửi config hợp lệ; secret lưu backend vault |
| Flow riêng | Mỗi công ty có flow riêng: prompt, tool, trigger, knowledge source, approval step, fallback human handoff | Domain entity `BotFlow`, `BotNode`, `ToolBinding` |
| Tool/API | VPSTTT order API chỉ là một tool mẫu, không là dependency cứng của app | Tool list lấy từ backend theo workspace |
| Test bot | Admin chạy thử prompt/flow bằng dữ liệu giả lập hoặc sample input | Use case `TestBotFlow` trả transcript và lỗi rõ |
| Audit | Lưu lịch sử ai action, tool call, người sửa flow, phiên bản config | Mobile hiển thị audit theo permission |
| Chat runtime | User chat với bot như conversation bình thường, có label bot và trạng thái đang trả lời | Presentation dùng cùng message timeline, không tạo UI riêng quá khác |

## 4. Stack đề xuất

| Thành phần | Lựa chọn |
|---|---|
| Flutter/Dart | Flutter stable, Dart stable đi kèm |
| State management | Riverpod/riverpod_generator, ưu tiên `AsyncNotifier`/`Notifier` theo feature |
| Navigation | `go_router` |
| REST | Client sinh từ OpenAPI + Dio transport/interceptor |
| Realtime | `web_socket_channel` |
| Secure storage | `flutter_secure_storage` |
| Local database | Drift + SQLite |
| Immutable/model | `freezed`/`json_serializable` cho UI model/data model khi generator contract không đủ |
| Push | Firebase Messaging; APNs qua Firebase cho iOS |
| Local notification | `flutter_local_notifications` |
| File/image | `file_picker`, `image_picker` |
| Voice | `record`, `just_audio` |
| Audio/video call | `flutter_webrtc`, permission qua `permission_handler` |
| Connectivity | `connectivity_plus` kết hợp request thực tế, không chỉ tin trạng thái mạng |
| Crash report | Sentry/Crashlytics có redaction; không gửi nội dung chat |

## 5. Cấu trúc source đề xuất

```text
mobile/
├── android/
├── ios/
├── assets/
├── integration_test/
├── lib/
│   ├── main.dart
│   ├── app/
│   │   ├── bootstrap.dart
│   │   ├── router.dart
│   │   └── theme/
│   ├── core/
│   │   ├── api/
│   │   ├── auth/
│   │   ├── database/
│   │   ├── error/
│   │   ├── realtime/
│   │   ├── security/
│   │   ├── sync/
│   │   └── telemetry/
│   └── features/
│       ├── auth/
│       ├── workspace/
│       ├── conversations/
│       ├── channels/
│       ├── messages/
│       ├── files/
│       ├── notifications/
│       ├── calls/
│       ├── profile/
│       ├── departments/
│       ├── bots/
│       ├── bot_flows/
│       ├── automation/
│       ├── tickets/
│       ├── admin/
│       ├── super_admin/
│       └── settings/
├── test/
└── pubspec.yaml
```

Mỗi feature chia `data`, `domain`, `application` và `presentation` ở mức vừa đủ; không tạo abstraction hình thức nếu feature nhỏ.

Mẫu cấu trúc một feature lớn:

```text
features/messages/
├── domain/
│   ├── entities/message.dart
│   ├── repositories/message_repository.dart
│   ├── value_objects/message_id.dart
│   └── errors/message_failure.dart
├── application/
│   ├── send_message_use_case.dart
│   ├── observe_timeline_use_case.dart
│   ├── mark_read_use_case.dart
│   └── message_event_reducer.dart
├── data/
│   ├── datasources/message_remote_data_source.dart
│   ├── datasources/message_local_data_source.dart
│   ├── dto/message_dto.dart
│   ├── mappers/message_mapper.dart
│   └── repositories/message_repository_impl.dart
└── presentation/
    ├── controllers/message_timeline_controller.dart
    ├── screens/chat_room_screen.dart
    ├── widgets/message_bubble.dart
    └── models/message_view_model.dart
```

### 5.1. Ranh giới package đề xuất khi app lớn dần

| Package/module | Nội dung | Khi nào tách |
|---|---|---|
| `app` | Bootstrap, route, flavor, root provider scope | Luôn có |
| `core` | Error, result, clock, id generator, logger, permission abstraction | Luôn có |
| `design_system` | Token màu, typography, button, avatar, badge, bottom sheet, empty state | Sau M1 để tránh copy widget |
| `api_client` | Generated OpenAPI client và Dio adapter | Ngay M0/M1 |
| `local_store` | Drift database, migration, DAO base | Ngay M1/M8 |
| `realtime` | WebSocket connection, event envelope, reconnect/catch-up | Ngay M5 |
| `feature_*` | Feature độc lập khi code vượt khoảng 1.500-2.000 dòng hoặc cần owner riêng | Tách dần, không tách sớm hình thức |

## 6. Phạm vi chức năng hoàn chỉnh

| Nhóm | Chức năng phải có |
|---|---|
| Auth | Login email/username, Google khi cấu hình, refresh, logout, remember login, session list/revoke |
| Workspace/RBAC | Chọn workspace/công ty, permission gate, membership, chuyển workspace, profile, quyền admin/super admin |
| Conversation | DM, channel public/private/group, unread, favorite, search, read state |
| Message | Text, markdown, emoji, mention, reaction, reply, thread, pin, forward, edit, recall/delete |
| Media | Camera, gallery, file, paste/share intent, voice record/play, video, preview/download |
| Call | Audio call, video call, incoming ringing, missed call, call history, permission camera/mic, reconnect/hangup |
| Realtime | Message, typing, reaction, pin, update/delete, notification, presence, reconnect/catch-up |
| Notification | FCM/APNs, local notification, badge, deep link, mark read, preference, mute/quiet hours |
| Offline | Cache đọc, draft, outbox, upload queue, retry/idempotency, migration/eviction |
| Phòng ban | Cây, chi tiết, member và channel liên kết theo permission |
| Bot/AI | Bot theo workspace, cấu hình provider/model/prompt/tool/flow/knowledge, test bot, audit, handoff sang người thật |
| Automation | Danh sách, CRUD, run-now, pause/resume, lịch sử, webhook theo permission |
| Ticket | Lifecycle đầy đủ sau khi backend ticket domain/API thật hoàn thành |
| Admin | Workspace admin quản lý thành viên, kênh, bot, ticket, automation ở mức mobile-friendly |
| Super admin | Xem danh sách workspace, trạng thái hệ thống, nhảy vào workspace theo quyền được cấp |
| Native | Deep link/universal link, share intent, biometric app lock, camera/mic permission, background lifecycle |
| Accessibility | Font scaling, screen reader, contrast, touch target, reduced motion |

### 6.1. Bản đồ màn hình mobile

| Khu vực | Màn hình chính | Màn hình phụ/bottom sheet | Ghi chú UX |
|---|---|---|---|
| Onboarding/Auth | Splash, login, chọn workspace | Quên mật khẩu, revoke session, chọn môi trường dev/staging nếu build nội bộ | Không hiện route chat khi chưa có workspace hợp lệ |
| Home | Danh sách hội thoại, channel, unread, favorite | Search, filter, create DM/channel | Phone dùng single column; tablet dùng split view |
| Chat | Timeline, composer, reaction, reply, pin, media, call button | Message actions, emoji picker, member list, pinned/media/file tabs | Composer phải bám safe area và không mất draft |
| Call | Incoming call, outgoing call, active audio/video call | Chọn camera/mic/speaker, reconnect, call ended/missed card | Sự kiện call lưu như message system |
| Bot/AI | Bot conversation, bot list | Bot detail, test prompt, flow status, handoff | Admin mới thấy config; user chỉ chat |
| Ticket | Ticket list, ticket detail | Assign, status, priority, comment, attachment | Toàn bộ tiếng Việt có dấu |
| Admin | Member, role, channel request, bot flow, automation | Confirm destructive action, audit view | Có thể mở Admin Panel web cho chức năng quá nặng |
| Super admin | Workspace list, workspace health | Switch workspace, suspend/activate theo quyền | Không dùng cho member thường |

### 6.2. Reference UI bắt buộc

Mobile app phải thiết kế dựa trên mẫu Zalo-like/WebTui mobile đã chốt. Ảnh reference chính đặt tại:

```text
docs/design/mobile/references/webtui-mobile-zalo-reference.png
```

Tài liệu phân tích reference đặt tại:

```text
docs/design/mobile/references/mobile-ui-reference.md
```

Quy tắc khi làm UI mobile:

- Trước khi dựng bất kỳ màn Flutter nào, phải mở ảnh reference, đọc kế hoạch dùng skill ở mục 6.3 và chỉ dùng các skill thiết kế mobile được phép cho phần định hướng UI.
- UI ưu tiên cảm giác ứng dụng chat native chuyên nghiệp: nền sáng, border mảnh, shadow nhẹ, danh sách dày nhưng dễ quét, tab segmented nhỏ, bottom navigation rõ.
- Màn đầu tiên không làm landing page marketing; phải là trải nghiệm app thật: đăng nhập, tin nhắn, danh bạ, kênh/bot, cài đặt.
- Luồng `Tin nhắn`, `Bạn bè`, `Kênh & Bot`, `Kênh`, `Cài đặt` phải bám bố cục và mật độ của ảnh mẫu.
- Tất cả label, empty state, toast, lỗi và mô tả trong UI phải là tiếng Việt có dấu.
- Sau khi hoàn thành UI, phải chụp screenshot mobile và đối chiếu lại với ảnh reference; nếu lệch navigation, spacing, mật độ list hoặc phong cách Zalo-like thì chưa đạt.

### 6.3. Kế hoạch dùng skill cho thiết kế mobile

Phạm vi này chỉ áp dụng cho thiết kế, visual planning, mockup và audit UI mobile. Không dùng skill web/desktop/architecture để định hướng giao diện mobile nếu không có yêu cầu riêng. Mục tiêu là giữ mọi màn hình giống app native thật, không biến mobile thành landing page hoặc web thu nhỏ trong khung điện thoại.

| Skill | Vai trò | Khi dùng | Không dùng cho |
|---|---|---|---|
| `imagegen-frontend-mobile` | Skill chính cho mobile screen concept | Tạo concept màn hình, flow nhiều màn, onboarding, auth, chat, settings, admin-friendly mobile view; khóa platform mode, design bible, phone mockup, safe area, readability và screen consistency | Không viết code Flutter/React/HTML, không làm landing page hoặc dashboard web |
| `brandkit` | Nền nhận diện trước khi thiết kế màn | Khi cần chốt logo direction, palette, typography mood, icon language, texture và brand board cho WebTui Chat/mobile | Không thay thế screen flow, không quyết định layout chi tiết từng màn app |
| `redesign-existing-projects` | Audit và nâng cấp UI mobile đã có | Khi đã có Flutter screen/screenshot để scan, diagnose và đề xuất fix các dấu hiệu generic, spacing yếu, state thiếu, text overflow, component quá web-like | Không rewrite từ đầu, không áp dụng mẫu marketing/web app lên mobile |
| `gpt-taste` | Tham khảo taste, hierarchy và anti-generic checklist | Dùng như checklist phụ để tăng chất lượng thị giác: spacing rộng vừa đủ, typography có nhịp, bố cục bớt lặp, motion-implied cues cho mockup | Không dùng AIDA/hero/GSAP/web section rules làm yêu cầu cho mobile app; không sinh code motion nếu phase không yêu cầu |

Luồng routing bắt buộc cho mọi thiết kế mobile:

1. Nếu chưa chốt nhận diện, dùng `brandkit` trước để tạo brand direction ngắn: core metaphor, palette, type mood, icon style, texture.
2. Với mọi flow hoặc màn mới, dùng `imagegen-frontend-mobile` làm skill điều phối chính: chọn platform mode, số màn, design bible, navigation model, safe area, phone mockup và acceptance về readability.
3. Nếu đã có UI Flutter hoặc screenshot, dùng `redesign-existing-projects` sau `imagegen-frontend-mobile` để audit lệch chuẩn và lập danh sách fix có phạm vi.
4. Chỉ dùng `gpt-taste` như checklist phụ cho premium taste; bỏ qua toàn bộ yêu cầu web-only như landing hero, AIDA page, GSAP ScrollTrigger, bento desktop.
5. Bàn giao thiết kế phải có: skill routing đã chọn, design bible, screen map, màn nào cần mockup/generated image, màn nào implement Flutter, và checklist đối chiếu screenshot sau khi code.

Acceptance cho planning thiết kế mobile:

- Mọi flow có thứ tự màn hợp lý, ví dụ onboarding -> auth -> home hoặc conversation list -> chat -> action sheet.
- Màn đầu tiên là trải nghiệm app thật, không phải hero marketing.
- Navigation, safe area, bottom tab, list density, touch target và keyboard region được nêu rõ.
- Text tiếng Việt có dấu, ngắn, đọc được ở kích thước mobile.
- Không dùng skill ngoài `brandkit`, `gpt-taste`, `imagegen-frontend-mobile`, `redesign-existing-projects` cho phần thiết kế/concept/audit UI mobile.

## 7. Bảng phase tổng quan

| Phase | Tên | Kết quả bàn giao | Điều kiện chuyển phase |
|---|---|---|---|
| M0 | Contract và mobile readiness | API gap list, generated client, ADR | Contract mobile được khóa |
| M1 | Flutter foundation | App flavors, theme, router, DI/state, CI nền | Analyze/test/build Android pass |
| M2 | Auth và secure session | Login/refresh/logout/session | Token được lưu an toàn |
| M3 | Workspace, RBAC và profile | Chọn workspace/hồ sơ/settings | Data scope và permission đúng |
| M4 | Conversation và channel | Danh sách DM/channel, unread/search | Điều hướng mobile hoàn chỉnh |
| M5 | Message và realtime | Chat nâng cao, typing/presence/reconnect | Hai thiết bị nhận event đúng |
| M6 | Media, voice note và audio/video call | Media flow, call signaling và WebRTC cơ bản | Upload/record/play/download/call pass |
| M7 | Push, background và deep link | FCM/APNs, badge, notification preference | Push mở đúng message |
| M8 | Offline, sync và reliability | Cache/outbox/idempotency | Mạng yếu không mất/trùng dữ liệu |
| M9 | Module nghiệp vụ đầy đủ | Phòng ban, bot, automation, ticket | Không còn placeholder thuộc scope |
| M10 | Native UX, accessibility và performance | Biometric/share/accessibility/tối ưu | Đạt quality gate thiết bị thật |
| M11 | Test, security và Android packaging | Signed APK/AAB, Firebase distribution, direct download fallback | Người dùng nội bộ tải/cài được bản Android |
| M12 | CH Play và kênh tải Android | Play Console, store listing, internal/closed/open/production track, download page | Người dùng tải được qua CH Play hoặc link APK có kiểm soát |
| M13 | iOS hardening và release | TestFlight/App Store | iOS production ready |

### 7.1. Ma trận task Clean Architecture xuyên suốt

| ID | Hạng mục | Việc phải làm | Acceptance |
|---|---|---|---|
| CA-1 | Dependency rule | Thêm lint/import rule hoặc review checklist chặn `presentation` import trực tiếp `dio`, `drift`, `firebase_*`, generated DTO | CI hoặc review fail khi vi phạm |
| CA-2 | Feature template | Tạo template thư mục `domain/application/data/presentation` và README feature | Feature mới không tự phát minh cấu trúc |
| CA-3 | Result/error model | Chuẩn hóa `Result<T, Failure>`, `AppFailure`, mapping HTTP/domain/local error | UI không parse status code/raw exception |
| CA-4 | Repository contract | Mỗi feature có interface ở domain và impl ở data | Unit test use case dùng fake repository |
| CA-5 | Mapper boundary | DTO/entity/view model có mapper rõ, không dùng một model cho mọi layer | DTO không xuất hiện trong widget |
| CA-6 | Use case catalog | Danh sách use case chính cho từng feature, đặt tên theo hành động nghiệp vụ | Controller chỉ gọi use case, không tự ghép API |
| CA-7 | Provider composition | Riverpod provider chỉ inject dependency, observe state và gọi use case | Không chứa query SQL/URL API trong provider UI |
| CA-8 | Realtime reducer | Event websocket được đưa qua reducer/application service | Không update timeline trực tiếp trong socket callback của widget |
| CA-9 | Offline outbox | Mutation quan trọng có command/outbox/idempotency | Gửi lại không tạo dữ liệu trùng |
| CA-10 | Test pyramid | Domain/use case test nhiều nhất, widget test cho UI state, integration test cho flow thật | Mỗi phase có test tương ứng |
| CA-11 | Tenant guard | Mọi query/cache/event command có `workspace_id` hoặc session scope rõ | Không có dữ liệu chéo workspace trong local DB |
| CA-12 | Secret boundary | Secret/token/API key chỉ qua abstraction bảo mật | Log/crash/cache không chứa secret |

## Phase M0: Contract và backend mobile readiness

| Task | Công việc | Phụ thuộc | Kết quả/Acceptance | Ưu tiên |
|---|---|---|---|---|
| M0.1 | Lập ma trận parity web → mobile | Không | Mọi chức năng có phase/owner | P0 |
| M0.2 | Đối chiếu OpenAPI với route Go | Không | Không thiếu endpoint mobile cần | P0 |
| M0.3 | Hoàn thiện schema/error/meta/event | M0.2 | Dart generator đọc được contract không lỗi | P0 |
| M0.4 | Sinh Dart client tự động | M0.3 | Model/request/response không viết tay trùng lặp | P0 |
| M0.5 | Contract test trong CI | M0.3 | Route/schema lệch làm CI fail | P0 |
| M0.6 | Thiết kế device registration API | M0.2 | Register/update/unregister token và platform | P0 |
| M0.7 | Thiết kế notification preference API | M0.6 | all/mention/mute/quiet hours/preview policy | P0 |
| M0.8 | Thiết kế message idempotency | M0.2 | Retry cùng client ID chỉ tạo một message | P0 |
| M0.9 | Thiết kế sync/catch-up cursor | M0.2 | Phục hồi sau background/offline dài | P0 |
| M0.10 | Chốt Android-first và device matrix | Không | Danh sách Android/iOS version hỗ trợ | P0 |
| M0.11 | Chốt privacy/data retention | Không | Cache/push/crash log có policy rõ | P0 |

Điều kiện hoàn thành M0: generated client build được, API push/idempotency/sync có contract và không còn endpoint giả định.

## Phase M1: Flutter foundation và design system

| Task | Công việc | Phụ thuộc | Kết quả/Acceptance | Ưu tiên |
|---|---|---|---|---|
| M1.1 | Scaffold Flutter app | M0 | Android/iOS project và package ID ổn định | P0 |
| M1.2 | Tạo flavors dev/staging/prod | M1.1 | Base URL không hard-code và không trỏ localhost ở prod | P0 |
| M1.3 | Theme sáng/tối VPSTTT | M1.1 | Token màu, typography, spacing, component nền | P0 |
| M1.4 | Router và auth guard | M1.1 | Deep route chuẩn bị từ đầu | P0 |
| M1.5 | Riverpod provider architecture | M1.1 | Scope provider rõ, không global mutable state tùy tiện | P0 |
| M1.6 | API interceptor/error mapper | M0.4 | Envelope, 401 refresh, request ID và lỗi tiếng Việt | P0 |
| M1.7 | Local database foundation | M1.1 | Drift schema/version/migration test | P0 |
| M1.8 | Logging có redaction | M1.1 | Không log token/message/file path nhạy cảm | P0 |
| M1.9 | Widget loading/empty/error/toast | M1.3 | Trạng thái dùng nhất quán toàn app | P0 |
| M1.10 | CI nền | M1.1 | format/analyze/test/build APK chạy tự động | P0 |
| M1.11 | Khóa mobile UI reference | Không | Ảnh mẫu nằm ở `docs/design/mobile/references/webtui-mobile-zalo-reference.png` và tài liệu phân tích reference được cập nhật | P0 |
| M1.12 | Khóa skill-routing thiết kế mobile | M1.11 | Prompt/UI planning chỉ dùng `brandkit`, `gpt-taste`, `imagegen-frontend-mobile`, `redesign-existing-projects` theo vai trò ở mục 6.3 | P0 |
| M1.13 | Design tokens từ ảnh mẫu | M1.11 | Màu, typography, spacing, radius, shadow, list density, bottom tab và segmented control được ghi thành guideline | P0 |

## Phase M2: Auth, secure session và app lock

| Task | Công việc | Phụ thuộc | Kết quả/Acceptance | Ưu tiên |
|---|---|---|---|---|
| M2.1 | Secure token repository | M1 | Refresh token trong Keystore/Keychain; access token memory | P0 |
| M2.2 | Login email/username | M2.1 | Error/rate-limit/loading đúng | P0 |
| M2.3 | Refresh queue | M2.1 | Nhiều request 401 chỉ refresh một lần | P0 |
| M2.4 | Logout và clear local state | M2.2 | Token/cache nhạy cảm/outbox theo policy được xử lý | P0 |
| M2.5 | Google Sign-In | Backend/provider config | OAuth native và backend exchange an toàn | P1 |
| M2.6 | Session list/revoke | M2.2 | Thu hồi thiết bị hiện tại làm app logout | P0 |
| M2.7 | Device identity | M2.2 | Device ID ổn định, không dùng hardware identifier nhạy cảm | P0 |
| M2.8 | Biometric/PIN app lock tùy chọn | M2.1 | Không thay thế backend auth; chỉ bảo vệ app cục bộ | P1 |
| M2.9 | Background screenshot privacy | M2.8 | App switcher có thể che nội dung nhạy cảm | P1 |

## Phase M3: Workspace, RBAC, profile và settings

| Task | Công việc | Phụ thuộc | Kết quả/Acceptance | Ưu tiên |
|---|---|---|---|---|
| M3.1 | List/select workspace | M2 | Khôi phục workspace cuối nếu membership còn hợp lệ | P0 |
| M3.2 | Permission repository | M3.1 | Gate bằng code từ `/rbac/me` | P0 |
| M3.3 | Workspace switch isolation | M3.1 | Cache/database/query không lẫn tenant | P0 |
| M3.4 | Profile view/update | M2 | Display name, phone, avatar dùng API thật | P0 |
| M3.5 | Avatar camera/gallery/upload | M3.4 | Crop/compress/permission/error đầy đủ | P0 |
| M3.6 | Theme/language/notification settings | M1/M7 | Lưu local và sync preference khi có API | P0 |
| M3.7 | Privacy/session screen | M2.6 | Revoke và logout-all có confirm | P0 |
| M3.8 | Permission denied UX | M3.2 | 403 không biến thành lỗi hệ thống chung | P0 |

## Phase M4: Hội thoại, channel và mobile navigation

| Task | Công việc | Phụ thuộc | Kết quả/Acceptance | Ưu tiên |
|---|---|---|---|---|
| M4.1 | Conversation list screen | M3 | DM/channel preview, time, unread, avatar/status | P0 |
| M4.2 | Tabs tất cả/chưa đọc/yêu thích | M4.1 | Filter đồng bộ read/favorite state | P0 |
| M4.3 | Search conversation/user/channel | M4.1 | Debounce, empty/error và permission đúng | P0 |
| M4.4 | Direct conversation create/open | M3.2 | Không tạo DM duplicate | P0 |
| M4.5 | Channel public/private/group list | M3.2 | Chỉ hiển thị channel user được phép | P0 |
| M4.6 | Create/join/invite/request channel | M3.2 | Mutation và approval flow đầy đủ | P0 |
| M4.7 | Channel details/member | M4.5 | Member/pin/media/file/settings trong màn riêng/bottom sheet | P0 |
| M4.8 | Read state/unread badge | M4.1 | Mở/scroll đọc cập nhật đúng API | P0 |
| M4.9 | Mobile navigation state | M4.1 | Back gesture/system back không mất draft | P0 |
| M4.10 | Tablet adaptive layout | M4.1 | Tablet có list-detail, phone dùng từng màn | P1 |

## Phase M5: Tin nhắn và realtime

| Task | Công việc | Phụ thuộc | Kết quả/Acceptance | Ưu tiên |
|---|---|---|---|---|
| M5.1 | Cursor timeline và reverse list | M4 | Load cũ không nhảy scroll | P0 |
| M5.2 | Composer text/markdown/emoji/mention | M5.1 | Draft, keyboard, safe area và limit đúng | P0 |
| M5.3 | Edit/delete/recall | M5.2 | Permission/owner đúng, UI cập nhật realtime | P0 |
| M5.4 | Reaction picker và summary | M5.2 | Add/remove/count không trùng | P0 |
| M5.5 | Reply/thread | M5.2 | Thread screen có pagination/composer riêng | P0 |
| M5.6 | Pin/unpin | M5.2 | Pin list và event realtime đúng | P0 |
| M5.7 | Forward | M5.2 | Chọn đích, membership và attachment đúng | P0 |
| M5.8 | Message search/filter | M5.1 | Date/sender/type/channel và jump-to-message | P0 |
| M5.9 | WebSocket manager | M2/M3 | Auth, join/leave, backoff, lifecycle | P0 |
| M5.10 | Realtime event reducer | M5.9 | Create/update/delete/reaction/pin/notification merge idempotent | P0 |
| M5.11 | Typing/presence | M5.9 | Throttle/timeout/background behavior đúng | P0 |
| M5.12 | Foreground catch-up | M5.9/M0.9 | Quay lại app không bỏ sót tin | P0 |

## Phase M6: Ảnh, file, camera, voice, video và call

Tiến độ hiện tại 2026-07-17: đã bắt đầu M6 ở mức foundation với camera/gallery image picker, upload queue, attach file vào message, render attachment trong timeline, call domain/repository/use case và outgoing call entry point. Phần còn lại cần native/plugin/WebRTC gồm file picker đầy đủ, viewer/download/share, voice record/play, incoming call, active audio/video call và push bridge.

| Task | Công việc | Phụ thuộc | Kết quả/Acceptance | Ưu tiên |
|---|---|---|---|---|
| M6.1 | Camera/gallery picker | M5 | Permission denied/permanently denied có hướng dẫn | P0 |
| M6.2 | File picker | M5 | MIME/size validation trước upload | P0 |
| M6.3 | Image resize/compress/EXIF policy | M6.1 | Giảm dung lượng và xử lý orientation/privacy | P1 |
| M6.4 | Upload queue/progress | M6.1-M6.2 | Multiple upload, cancel, retry, background state | P0 |
| M6.5 | Attach file vào message | M6.4 | Message/attachment liên kết đúng API | P0 |
| M6.6 | Image gallery/viewer | M6.5 | Zoom, swipe, save/share theo permission | P0 |
| M6.7 | File download/open/share | M6.5 | Scoped storage và MIME intent đúng | P0 |
| M6.8 | Voice recorder | M5 | Hold/tap record, timer, cancel, preview trước gửi | P0 |
| M6.9 | Voice player | M6.8 | Play/pause/seek/speed/progress; một audio cùng lúc | P0 |
| M6.10 | Video player | M6.5 | Streaming/download/error/fullscreen cơ bản | P1 |
| M6.11 | Share intent vào WebTui | M6.2 | Nhận ảnh/file/text từ app khác và chọn conversation | P1 |
| M6.12 | File security state | Backend scan API | Scanning/quarantine không cho mở file nguy hiểm | P1 |
| M6.13 | Call domain model | M5 | `CallSession`, `CallParticipant`, `CallState`, `CallDirection`, `CallEndReason` test được ở domain | P0 |
| M6.14 | Call signaling repository | Backend call API/WebSocket | Invite/accept/reject/cancel/hangup/timeout/reconnect qua use case, không gọi socket từ widget | P0 |
| M6.15 | Incoming call UX | M6.14 | Bên nhận thấy màn hình/cuộc gọi đến, có chuông/rung, accept/reject đúng | P0 |
| M6.16 | Outgoing call UX | M6.14 | Bên gọi thấy ringing/connecting/failed/timeout rõ ràng | P0 |
| M6.17 | Active audio call | M6.14 | Mic mute, speaker, timer, network drop/reconnect, hangup | P0 |
| M6.18 | Active video call | M6.17 | Camera on/off, switch camera, local/remote preview, permission camera/mic | P0 |
| M6.19 | Call event message card | M6.14 | Missed call, incoming answered, outgoing answered, duration, "Gọi lại" giống luồng chat | P0 |
| M6.20 | Call notification bridge | M6.15/M7 | Background push mở incoming call; foreground không tạo notification trùng | P0 |

## Phase M7: Native push, background và deep link

Tiến độ hiện tại 2026-07-17: M7 đã khóa phần mobile foundation gồm Firebase runtime options/background handler, push device register/update/unregister/token refresh, notification center, unread badge, mark read/read-all, preference sync, foreground push snackbar, duplicate suppression, deep-link target mở chat/highlight message, Android custom scheme/App Links manifest, iOS URL scheme và entitlement APS/Associated Domains. Phần còn lại cần xác nhận ngoài code bằng thiết bị thật, Firebase/APNs project thật, assetlinks/apple-app-site-association thật và backend worker delivery log.

| Task | Công việc | Phụ thuộc | Kết quả/Acceptance | Ưu tiên |
|---|---|---|---|---|
| M7.1 | Firebase project/flavor config | M1 | Dev/staging/prod tách project/token | P0 |
| M7.2 | Register/update/unregister push token | M0.6/M2 | Token refresh và logout xử lý đúng | P0 |
| M7.3 | Backend notification worker FCM/APNs | M0.6 | Retry/DLQ/idempotency và delivery log | P0 |
| M7.4 | Foreground local notification | M7.2 | Không hiển thị trùng khi đang mở đúng channel | P0 |
| M7.5 | Background/terminated notification | M7.3 | Nhận được khi app nền/bị kill theo OS policy | P0 |
| M7.6 | Badge count | M7.3 | Đồng bộ unread khi mark read/all read | P0 |
| M7.7 | Deep link/universal link/app link | M1/M4 | Mở đúng workspace/channel/message | P0 |
| M7.8 | Notification preference/mute | M0.7 | all/mention/mute/quiet hours/preview | P0 |
| M7.9 | Sensitive preview policy | M7.8 | Màn hình khóa ẩn nội dung theo setting | P0 |
| M7.10 | Duplicate suppression | M7.3-M7.4 | Một event không sinh hai notification | P0 |

## Phase M8: Offline, sync và reliability

Tiến độ hiện tại 2026-07-17: M8 đã hoàn thiện foundation trong mobile với cache conversation/channel/latest message page bằng AppDatabase, repository fallback khi API lỗi/offline, cache update sau send/edit/delete/reaction/pin/unpin/forward, local sync cursor theo workspace, `/sync` catch-up nhiều page kèm `/sync/ack`, auto catch-up khi đổi workspace hoặc app resume, message outbox scoped theo workspace/channel, `client_message_id` + `Idempotency-Key` khi retry, attachment retry từ file đã upload trong outbox, clear cache workspace không xóa draft/outbox, network quality banner khi catch-up lỗi và test cho cache/sync/outbox. Phần cần xác nhận ngoài code là chaos test airplane mode/process death với backend thật.

| Task | Công việc | Phụ thuộc | Kết quả/Acceptance | Ưu tiên |
|---|---|---|---|---|
| M8.1 | Cache workspace/conversation/message | M1/M5 | App mở offline xem dữ liệu gần nhất | P0 |
| M8.2 | Cache migration/versioning | M8.1 | Upgrade app không mất/crash database | P0 |
| M8.3 | Draft per conversation | M4/M5 | Draft qua restart và workspace switch đúng | P0 |
| M8.4 | Message outbox | M0.8/M5 | Pending/failed/sent có trạng thái rõ | P0 |
| M8.5 | Idempotent retry | M8.4 | Retry nhiều lần chỉ có một message server | P0 |
| M8.6 | Attachment outbox | M6/M8.4 | File retry độc lập, không nhân attachment | P0 |
| M8.7 | Reconnect sync/catch-up | M0.9/M5 | Không bỏ event sau offline/background | P0 |
| M8.8 | Conflict policy | M8.7 | Edit/delete/read state có quy tắc server-wins rõ | P1 |
| M8.9 | Cache eviction/storage settings | M8.1 | Giới hạn dung lượng, clear cache không xóa outbox/draft | P1 |
| M8.10 | Network quality UX | M8.4 | Banner offline/reconnecting và retry minh bạch | P0 |

## Phase M9: Module nghiệp vụ đầy đủ

Tiến độ hiện tại 2026-07-17: M9 đã có tab `Nghiệp vụ` trong mobile, lấy dữ liệu thật theo workspace cho phòng ban, ticket, bot catalog, AI config, bot flows/installations, test/publish bot flow, cronjob automation kèm run-now/pause/resume/disable, incoming/outgoing webhook, API token list/revoke, audit log, admin stats và admin health. Ticket lifecycle đã có list/create/status update theo backend hiện có. UI hiển thị lỗi theo từng module khi permission/API chưa mở, không lưu secret webhook/API token trong cache. Phần còn cần backend/API bổ sung hoặc smoke test thật là ticket comment/attachment, flow rollback, announcement/system message, admin external link/browser và super-admin mobile.

| Task | Công việc | Phụ thuộc | Kết quả/Acceptance | Ưu tiên |
|---|---|---|---|---|
| M9.1 | Phòng ban | M3 | Cây, chi tiết, member, channel liên kết theo permission | P0 |
| M9.2 | Bot catalog theo workspace | M3 | Danh sách bot, trạng thái, kênh gắn bot, session riêng theo workspace | P0 |
| M9.3 | AI provider/model config | Backend AI config API | Workspace admin cấu hình provider/model qua backend, không nhập/lưu secret plaintext trong mobile | P0 |
| M9.4 | Bot flow mobile-friendly | M9.2-M9.3 | Xem/sửa flow dạng form đơn giản: prompt, trigger, fallback, handoff, approval | P0 |
| M9.5 | Tool binding và knowledge source | M9.4 | Tool/API/knowledge lấy từ backend theo workspace; VPSTTT order chỉ là một tool tùy chọn | P0 |
| M9.6 | Test bot flow | M9.4 | Admin chạy thử input mẫu, xem transcript/tool call/lỗi bằng tiếng Việt có dấu | P0 |
| M9.7 | Bot audit và version | M9.4 | Xem ai sửa flow, version, publish/rollback theo quyền | P1 |
| M9.8 | Automation list/detail | M3 | Status, next run và history | P0 |
| M9.9 | Automation CRUD/run/pause | M9.8 | Permission gate và API mutation đầy đủ | P0 |
| M9.10 | Webhook/API token screens theo quyền | M9.8 | Secret không lưu cache/log trái policy | P1 |
| M9.11 | Ticket lifecycle | Backend ticket API | Tạo/phân công/trạng thái/comment/attachment/notification | P0 trước final parity |
| M9.12 | Announcement/system message | Backend producer | Hiển thị/acknowledge theo contract | P1 |
| M9.13 | Admin external link | M3.2 | Chỉ admin thấy link mở Admin Panel browser | P1 |
| M9.14 | Workspace admin mobile | Backend admin API | Quản lý thành viên, role, channel request, bot/automation cơ bản theo permission | P1 |
| M9.15 | Super admin mobile | Backend super admin API | Xem workspace, trạng thái, chuyển workspace theo quyền, không trộn cache tenant | P1 |

## Phase M10: Native UX, accessibility và performance

Tiến độ hiện tại 2026-07-17: M10 đã có foundation cho permission rationale trong attachment sheet, keyboard safe area, touch target theme, text-scale clamp 0.85-1.35, locale/delegates `vi/en`, chat lifecycle suspend/resume realtime khi app vào nền, reduced-motion cho highlight/scroll, semantics label cho message row, timeline `ListView.builder` cache/repaint tuning và mobile release/version gate trong Settings dùng endpoint `/mobile/releases/{platform}/{channel}/{current_version}`. Phần còn cần xác nhận trên thiết bị thật là TalkBack/VoiceOver, font lớn, rotation/tablet, timeline rất lớn, gallery nhiều ảnh và policy bắt buộc update.

| Task | Công việc | Phụ thuộc | Kết quả/Acceptance | Ưu tiên |
|---|---|---|---|---|
| M10.1 | Android/iOS permission UX | M6/M7 | Camera/mic/photo/notification có rationale và settings link | P0 |
| M10.2 | Keyboard/safe area/rotation | M4-M6 | Composer không bị che, tablet/landscape dùng được | P0 |
| M10.3 | Accessibility semantics | M1 | TalkBack/VoiceOver đọc đúng message/action/status | P0 |
| M10.4 | Dynamic font/touch target/contrast | M1 | Không vỡ layout ở font lớn | P0 |
| M10.5 | Reduced motion | M1 | Animation tuân thủ setting hệ điều hành | P1 |
| M10.6 | Timeline virtualization/performance | M5 | Cuộn channel lớn mượt trên thiết bị tầm trung | P0 |
| M10.7 | Image/memory optimization | M6 | Không OOM khi mở gallery/channel nhiều ảnh | P0 |
| M10.8 | Battery/background optimization | M5/M7 | Không giữ WebSocket/heartbeat trái lifecycle | P0 |
| M10.9 | Localization | M1 | Tiếng Việt hoàn chỉnh, sẵn đường thêm ngôn ngữ | P1 |
| M10.10 | App update/version gate | Backend version API | Cảnh báo/bắt buộc update khi contract không tương thích | P0 |

## Phase M11: Test, security và Android packaging

Tiến độ hiện tại 2026-07-17: M11 đã có test bổ sung cho mobile release policy và push deep-link security, integration smoke test, workflow `.github/workflows/mobile.yml` chạy format/architecture/analyze/test/integration/debug APK, release job signed AAB/APK bằng GitHub secrets, checksum SHA-256 và `mobile-release-manifest.json`. Android release signing đọc `android/key.properties`/env, không dùng debug signing cho release; docs nội bộ đã có Android distribution, release security checklist, device matrix, Android direct download plan và source trang tải tĩnh trong `deploy/download/`. Phần còn cần môi trường thật là upload Firebase/Play Internal, kiểm thử thiết bị vật lý, publish manifest lên backend/download host và xác nhận signing secret trong GitHub protected environment.

| Task | Công việc | Phụ thuộc | Kết quả/Acceptance | Ưu tiên |
|---|---|---|---|---|
| M11.1 | Unit test domain/repository | M2-M9 | Auth, reducer, sync, outbox, permission được test | P0 |
| M11.2 | Widget/golden test | M1-M10 | Login/list/timeline/composer/error/theme pass | P0 |
| M11.3 | Integration E2E | M2-M9 | Login → chat → file → voice → push → deep link pass | P0 |
| M11.4 | Realtime multi-device test | M5 | Create/update/delete/reaction/read/presence đúng | P0 |
| M11.5 | Offline/network chaos test | M8 | Airplane mode, timeout, token expiry, process death pass | P0 |
| M11.6 | Security test | M2/M7/M8 | Token/cache/log/deep link/push payload được audit | P0 |
| M11.7 | Device matrix Android | M10 | OS/version/screen/device tầm thấp-trung-cao | P0 |
| M11.8 | Workflow `mobile.yml` | M1 | analyze/test/build/sign/upload artifact | P0 |
| M11.9 | Chốt `applicationId`/package name | M1 | Package name production ổn định; hiểu rằng khi upload Play Console lần đầu sẽ bị khóa | P0 |
| M11.10 | Android signing setup | M11.8 | Tạo upload keystore, lưu secret trong CI, không commit `.jks`/password; quyết định dùng Play App Signing | P0 |
| M11.11 | Build signed AAB/APK | M11.10 | Sinh được `.aab` cho CH Play và `.apk` cho tải trực tiếp/test; versionCode tăng tự động | P0 |
| M11.12 | Debug symbols/mapping | M11.11 | Upload mapping/native symbols nếu có để đọc crash/ANR đúng | P1 |
| M11.13 | Firebase App Distribution | M11.11 | Nhóm nội bộ nhận email/link và cài được bản test trên thiết bị thật | P0 |
| M11.14 | Direct APK download fallback | M11.11 | Upload APK lên `chat.vpsttt.com/downloads/files/android/stable/`, có checksum SHA-256, version, release notes và hướng dẫn cài | P0 |
| M11.15 | Mobile update metadata | Backend version API | Web/mobile hiển thị bản mới, minimum version, recommended version và link tải phù hợp | P0 |
| M11.16 | Tài liệu cài Android nội bộ | M11.13-M11.14 | Có hướng dẫn rõ cho Firebase, CH Play internal test và APK sideload | P0 |

## Phase M12: CH Play và kênh tải Android

Tiến độ hiện tại 2026-07-17: M12 đã có Play Console readiness doc, privacy policy draft, permission/data safety checklist, download page spec, download host manifest example, release readiness gate trong `tool/check_mobile_release.dart` và source trang tải Android-first ở `deploy/download/`. Trước mắt ưu tiên `chat.vpsttt.com/download/` cho APK signed kèm SHA-256/release notes; CH Play bật sau bằng `store_url` trong manifest. Ghi chú policy mới nhất: nguồn Google chính thức hiện nêu từ 31/08/2026 app mới/cập nhật phải target Android 16/API 36; trước mỗi release phải kiểm tra lại trang chính sách vì deadline có thể thay đổi. Phần còn cần môi trường ngoài repo là tạo Play Console app thật, enroll Play App Signing, upload AAB lên Internal/Closed track, chạy Pre-launch report, public privacy/support URLs và triển khai path tải trên `chat.vpsttt.com`.

| Task | Công việc | Phụ thuộc | Kết quả/Acceptance | Ưu tiên |
|---|---|---|---|---|
| M12.1 | Tạo Play Console app | M11.9 | App name, default language, app/game, free/paid, package name production được chốt | P0 |
| M12.2 | Play App Signing | M11.10 | App được enroll Play App Signing; lưu upload key an toàn; lấy SHA-1/SHA-256 cho OAuth/App Links | P0 |
| M12.3 | Target SDK/API compliance | M11.11 | Target API đáp ứng yêu cầu Google Play hiện hành; kiểm tra lại trước mỗi release lớn | P0 |
| M12.4 | Store listing assets | M1/M10 | Icon, screenshots phone/tablet, feature graphic, short/full description tiếng Việt có dấu | P0 |
| M12.5 | Privacy policy và support | M2/M7/M8 | URL privacy policy, email hỗ trợ, account deletion/export policy nếu áp dụng | P0 |
| M12.6 | Data safety/content rating | M2-M10 | Khai báo dữ liệu thu thập/chia sẻ, mã hóa, xóa dữ liệu, content rating đầy đủ | P0 |
| M12.7 | Permission declarations | M6/M7 | Camera, microphone, photo/file, notification, background/network permission có lý do đúng | P0 |
| M12.8 | Internal testing track | M11.11 | Tối đa nhóm tester nội bộ cài qua Play Store; link opt-in hoạt động | P0 |
| M12.9 | Closed/open testing track | M12.8 | Nhóm khách hàng/thử nghiệm nhận build qua Play, feedback được thu thập | P0 |
| M12.10 | Pre-launch report và Android vitals | M12.8 | Không còn crash/blocker lớn trong pre-launch report; crash/ANR metric đạt ngưỡng | P0 |
| M12.11 | Production staged rollout | M12.9-M12.10 | Rollout theo phần trăm, có khả năng pause/halt; monitoring active | P0 |
| M12.12 | Managed Google Play/private app | M12.1 | Nếu bán B2B theo workspace, có phương án private app cho tổ chức cần quản lý thiết bị | P1 |
| M12.13 | APK download public fallback | M11.14 | Nếu chưa public CH Play, người dùng vẫn tải được APK signed tại `chat.vpsttt.com/download/` kèm checksum | P0 |
| M12.14 | Landing/download page | M12.8/M12.13 | Đã có source static Android-first ở `deploy/download/`; trang đọc manifest, hiện APK signed, checksum, release notes và bật CH Play sau bằng `store_url` | P1 |

Ghi chú chính sách Android tại thời điểm cập nhật roadmap: Google Play yêu cầu app mới và bản cập nhật nhắm Android 15/API 35 hoặc cao hơn để gửi lên Play, trừ một số ngoại lệ thiết bị; cần kiểm tra lại yêu cầu này trước ngày release vì Google cập nhật hằng năm.

## Phase M13: iOS hardening và release

| Task | Công việc | Phụ thuộc | Kết quả/Acceptance | Ưu tiên |
|---|---|---|---|---|
| M13.1 | Bundle/signing/provisioning | M11 | Build signed trên macOS runner | P0 |
| M13.2 | APNs/Firebase push | M7 | Foreground/background/terminated pass trên thiết bị thật | P0 |
| M13.3 | Universal Links | M7 | Link đã xác minh domain mở đúng app/message | P0 |
| M13.4 | Keychain/biometric/privacy screen | M2/M10 | Security behavior đúng iOS | P0 |
| M13.5 | Camera/mic/photo/file UX | M6 | Permission và picker đúng iOS | P0 |
| M13.6 | Background/lifecycle test | M5/M7/M8 | Resume/catch-up không trùng/mất message | P0 |
| M13.7 | Privacy manifest/Store metadata | M10 | Khai báo data/permission đúng thực tế | P0 |
| M13.8 | TestFlight internal/external | M13.1-M13.7 | Nhóm test xác nhận parity | P0 |
| M13.9 | App Store submission/rollout | M13.8 | Release có monitoring và rollback version plan | P0 |

## 8. Backend backlog bắt buộc cho bản đầy đủ

| ID | Backend/API cần bổ sung | Lý do |
|---|---|---|
| MB-1 | `push_devices` và device register/update/delete API | FCM/APNs token lifecycle |
| MB-2 | Notification preference/mute/quiet hours | Push đúng lựa chọn và privacy |
| MB-3 | FCM/APNs worker, retry và delivery log | Push production ổn định |
| MB-4 | `Idempotency-Key`/`client_message_id` | Offline retry không tạo tin trùng |
| MB-5 | Sync/event cursor hoặc catch-up contract | Phục hồi sau background/offline |
| MB-6 | Minimum supported client version | Mobile release chậm hơn backend |
| MB-7 | Ticket domain/API thật | Xóa placeholder và đạt full parity |
| MB-8 | Upload resume/chunk nếu file lớn | Mạng mobile yếu và process interruption |
| MB-9 | Notification target chuẩn | Deep link workspace/channel/message ổn định |
| MB-10 | Account deletion/export policy nếu public store yêu cầu | Tuân thủ store/privacy policy |
| MB-11 | Call session/signaling API và WebSocket event | Audio/video call, ringing, missed/ended call card |
| MB-12 | Call push notification/call timeout worker | Bên nhận thấy cuộc gọi đến khi app nền hoặc bị kill theo giới hạn OS |
| MB-13 | Bot installation/config/flow API theo workspace | Mỗi công ty có bot/flow riêng, không hard-code VPSTTT |
| MB-14 | AI provider config và secret vault | Mobile không giữ API key, admin chỉ cấu hình tham chiếu/secret name |
| MB-15 | Tool registry/knowledge source API theo workspace | Bot dùng tool khác nhau theo công ty |
| MB-16 | Bot run/test/audit/version API | Test flow, publish/rollback và audit chỉnh sửa |
| MB-17 | Super admin workspace API | Mobile có thể hiển thị danh sách/trạng thái workspace theo quyền |
| MB-18 | Mobile release metadata/version API | App biết bản minimum/recommended, link CH Play/APK/TestFlight và release notes |
| MB-19 | Public download page và checksum manifest | Người dùng tải APK/Desktop đúng bản, có SHA-256 để kiểm tra |
| MB-20 | Account deletion/export endpoint nếu public store yêu cầu | Đáp ứng privacy policy và khai báo store |

## 9. CI/CD đề xuất

Tạo `.github/workflows/mobile.yml` gồm:

1. Checkout và setup Flutter stable có version pin.
2. `flutter pub get`, format check, analyze và unit/widget test.
3. Sinh Dart client/model và fail nếu diff chưa commit.
4. Build APK debug cho pull request.
5. Build signed APK và AAB cho staging/release bằng GitHub Environment secrets.
6. Upload APK staging lên Firebase App Distribution cho nhóm tester.
7. Upload AAB lên Play Internal/Closed track bằng Play Developer API khi release manager approve.
8. Upload APK fallback lên `chat.vpsttt.com/downloads/files/android/stable/` kèm SHA-256 checksum và release notes.
9. Chạy integration test trên emulator/device farm theo lịch.
10. macOS job riêng build/sign IPA và upload TestFlight.

## 10. Release checklist chung

- [ ] Không có mock/fallback dữ liệu mẫu trong flavor production.
- [ ] Refresh token chỉ nằm trong secure storage.
- [ ] Cache/outbox không lẫn workspace hoặc user.
- [ ] Session revoke làm thiết bị logout.
- [ ] Permission UI và lỗi 403 hoạt động đúng.
- [ ] Realtime/reconnect/catch-up không mất hoặc trùng message.
- [ ] Tin pending retry bằng idempotency key.
- [ ] Camera/file/voice/video pass trên thiết bị thật.
- [ ] Push foreground/background/terminated và deep link pass.
- [ ] Nội dung nhạy cảm có thể ẩn trên lock screen/app switcher.
- [ ] TalkBack/VoiceOver, font lớn và touch target đạt yêu cầu.
- [ ] Crash report/log không chứa token hoặc nội dung chat.
- [ ] Store privacy/permission declaration đúng thực tế.
- [ ] Android upload keystore, Play Console access và CI signing secret được bảo vệ bằng secret store.
- [ ] AAB dùng cho CH Play, APK signed dùng cho Firebase/direct download; versionCode luôn tăng.
- [ ] APK download public có SHA-256 checksum, release notes và hướng dẫn cài đặt rõ.
- [ ] Play Console có privacy policy, data safety, content rating, permission declaration và store listing đầy đủ.
- [ ] Internal/closed testing hoặc Firebase App Distribution đã chạy tối thiểu một vòng trên thiết bị thật.
- [ ] Production rollout có kế hoạch pause/rollback và monitoring crash/ANR.
- [ ] Có tài liệu hỗ trợ đăng nhập, notification, microphone, cache và logout.
- [ ] Các màn mobile P0 đã đối chiếu screenshot với `docs/design/mobile/references/webtui-mobile-zalo-reference.png`.
- [ ] Domain layer không import Flutter/Dio/Drift/Firebase/generated DTO.
- [ ] DTO không xuất hiện trong widget, controller hoặc use case.
- [ ] Mỗi feature P0 có repository interface, use case, mapper và test tối thiểu.
- [ ] Provider/controller không chứa URL API, query SQL hoặc logic tenant/permission phức tạp.
- [ ] Bot/AI không hard-code provider/tool/flow của VPSTTT; toàn bộ lấy theo workspace config.
- [ ] Cache, websocket event, notification và deep link đều có `workspace_id`/tenant context rõ.

## 11. Ước lượng

Với hai lập trình viên Flutter và một backend hỗ trợ bán thời gian:

| Mốc | Thời gian dự kiến |
|---|---:|
| M0-M2 foundation/auth | 3–4 tuần |
| M3-M5 workspace/chat/realtime | 4–5 tuần |
| M6-M8 media/push/offline | 4–5 tuần |
| M9-M10 module đầy đủ/hardening | 3–4 tuần, chưa tính ticket backend |
| M11 Android packaging/internal distribution | 1–2 tuần |
| M12 CH Play và kênh tải Android | 2–3 tuần, tùy tốc độ review và chuẩn bị tài khoản |
| M13 iOS release | 2–3 tuần |

Android MVP nội bộ nên được phát hành sau M8 qua Firebase App Distribution hoặc APK signed trên `chat.vpsttt.com/download/`. Production “đầy đủ toàn bộ chức năng” chỉ đạt khi M9-M13 và các backend backlog P0 hoàn thành.

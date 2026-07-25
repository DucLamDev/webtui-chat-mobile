# Trạng thái Mobile App Flutter

Ngày cập nhật: 2026-07-17

## Tóm tắt nhanh

Mobile app Flutter đã có foundation, auth/session, workspace/RBAC, profile/settings, conversation/channel, app shell mobile và Phase M5 message/realtime đã khóa P0+polish. Sau lượt rà soát ngày 2026-07-17, M7 đã khóa mobile foundation push/deep link, M8 đã có offline cache/outbox/sync/retry/network UX foundation, M9 đã có tab Nghiệp vụ lấy dữ liệu thật cho phòng ban, bot/AI, ticket, automation, webhook/API token, audit/admin health, M10 đã có native UX/accessibility/performance foundation, M11 đã có test/security/Android packaging foundation, và M12 đã có Android-first download foundation để phát APK signed trước khi lên CH Play.

| Phase | Trạng thái | Ghi chú |
|---|---|---|
| M0 Contract và mobile readiness | Đã khóa | Có roadmap, contract gap và API nền |
| M1 Flutter foundation | Đã khóa | `clients/mobile/pubspec.yaml`, app shell, Riverpod, go_router, Dio boundary, Drift/Secure Storage foundation |
| M2 Auth và secure session | Đã khóa | Login/register/session/refresh/logout/session revoke có use case và API thật |
| M3 Workspace, RBAC, profile và settings | Đã khóa | Permission-first workspace switch, avatar crop/downscale, confirm revoke/revoke-all session |
| M4 Conversation, channel và mobile navigation | Đã khóa | Search debounce, clear unread badge đồng nhất, phone/tablet chat navigation |
| M5 Message và realtime | Đã khóa P0+polish | Cursor page, actions, search jump, pinned quick bar, reducer, WebSocket join/typing/backoff, foreground catch-up, rich bubble, reaction/forward/thread polish |
| M6 Media, voice note và audio/video call | Đang triển khai foundation | Camera/gallery image picker, upload/attach file API, attachment queue/render, call domain/repository/use case, start audio/video call sheet |
| M7 Native push, background và deep link | Đã khóa mobile foundation | Firebase runtime env, device register/unregister, notification center, unread badge, mark read/all, preference sync, push target deep link, Android/iOS link config |
| M8 Offline, sync và reliability | Đã khóa mobile foundation | Cache fallback, message outbox, idempotent retry, sync cursor/catch-up, clear cache policy, network banner |
| M9 Module nghiệp vụ đầy đủ | Đã có mobile foundation | Tab Nghiệp vụ cho departments, tickets list/create/status, bots/AI/flows/test/publish, cronjobs run/pause/resume, webhooks, API token list/revoke, audit log, admin stats và admin health |
| M10 Native UX, accessibility và performance | Đã có mobile foundation | Permission rationale, lifecycle suspend/resume realtime, reduced motion, semantics message row, Settings version gate qua `/mobile/releases` |
| M11 Test, security và Android packaging | Đã có mobile foundation | Release workflow, signed AAB/APK secret path, checksum/manifest artifact, integration smoke, release security checklist, device matrix và Android direct download plan |
| M12 CH Play và kênh tải Android | Đã có Android-first download foundation | Play Console checklist, privacy policy draft, data safety/permission declaration, download spec, manifest example, static download page và release gate |

## Checklist M3

| Task | Trạng thái | Evidence |
|---|---|---|
| M3.1 List/select workspace | Xong | `WorkspaceSelectorScreen`, `LoadWorkspaceSessionUseCase`, `SelectWorkspaceUseCase` |
| M3.2 Permission repository | Xong | `PermissionRemoteDataSource` gọi `/api/v1/rbac/me` với `workspace_id` |
| M3.3 Workspace switch isolation | Xong | Đổi workspace kiểm RBAC trước khi lưu active workspace; draft key có `workspaceId:channelId` |
| M3.4 Profile view/update | Xong | `ProfileRemoteDataSource` dùng `/api/v1/users/me` |
| M3.5 Avatar camera/gallery/upload | Xong | Camera/gallery, center-crop vuông, downscale 1024px, upload qua workspace file API |
| M3.6 Theme/language/notification settings | Xong | `LocalAppSettingsRepository` lưu local; sync preference nối tiếp ở M7 |
| M3.7 Privacy/session screen | Xong | List/revoke session, confirm revoke, revoke-all và clear local session |
| M3.8 Permission denied UX | Xong | `PermissionDeniedView` và failure mapping tách 403 |

## Checklist M4

| Task | Trạng thái | Evidence |
|---|---|---|
| M4.1 Conversation list screen | Xong | DM/channel preview, time, unread, avatar/status |
| M4.2 Tabs tất cả/chưa đọc/yêu thích | Xong | `ConversationListFilter` |
| M4.3 Search conversation/user/channel | Xong | `WebTuiSearchBar` debounce 250ms |
| M4.4 Direct conversation create/open | Xong | `OpenDirectConversationUseCase` dedupe DM |
| M4.5 Channel public/private/group list | Xong | `listChannels` theo workspace |
| M4.6 Create/join/invite/request channel | Xong | Create, join request, invite, approve/reject |
| M4.7 Channel details/member | Xong | Member, join request, pin, media, file, settings tab |
| M4.8 Read state/unread badge | Xong | Mark read API và clear unread state |
| M4.9 Mobile navigation state | Xong | `PopScope` và `dispose` persist draft |
| M4.10 Tablet adaptive layout | Xong | List-detail width >= 720 |

## Checklist M5

| Task | Trạng thái | Evidence |
|---|---|---|
| M5.1 Cursor timeline và reverse list | Xong nền | `MessagePage`, `LoadMessagesUseCase`, `ChatRoomController.loadOlder`; query dùng `before` đúng backend |
| M5.2 Composer text/markdown/emoji/mention | Xong | Emoji tray, draft/safe area, reply/edit context; mention UUID được gửi qua `mentioned_user_ids`; bubble render `**bold**`, inline code và mention `<@id>` |
| M5.3 Edit/delete/recall | Xong | `EditMessageUseCase`, `DeleteMessageUseCase`, quick actions trong `ChatRoomScreen` |
| M5.4 Reaction picker và summary | Xong | Reaction palette nhiều emoji, toggle qua API, reaction summary merge bằng realtime reducer |
| M5.5 Reply/thread | Xong | Gửi `parent_id`, load thread API, thread panel có root preview, reply list và composer riêng |
| M5.6 Pin/unpin | Xong | `TogglePinMessageUseCase`, quick action pin/unpin, realtime reducer xử lý pin state, pinned quick bar để nhảy tới tin ghim |
| M5.7 Forward | Xong | `ForwardMessageUseCase`, bottom sheet chọn kênh API-backed, lọc kênh hiện tại và kênh chưa là thành viên |
| M5.8 Message search/filter | Xong | `SearchMessagesUseCase` hỗ trợ query/channel/sender/kind/date; UI hiện query, chip kết quả và jump-to-message trong channel |
| M5.9 WebSocket manager | Xong nền | `WebSocketConversationRealtimeRepository` auth token, join/leave room, reconnect backoff |
| M5.10 Realtime event reducer | Xong | `ConversationRealtimeReducer` merge idempotent create/update/delete/reaction/pin/typing |
| M5.11 Typing/presence | Xong nền | `SendTypingUseCase` throttle, `TypingStarted/TypingStopped`, typing indicator |
| M5.12 Foreground catch-up | Xong nền | `ChatRoomScreen` reload khi app resume |

## Checklist M6

| Task | Trạng thái | Evidence |
|---|---|---|
| M6.1 Camera/gallery picker | Xong foundation | `ImagePickerMessageAttachmentRepository`, composer attachment sheet chọn camera/gallery |
| M6.2 File picker | Chưa làm native | Cần thêm `file_picker` hoặc wrapper native riêng; hiện UI ghi rõ tệp/ghi âm là bước M6 tiếp theo |
| M6.3 Image resize/compress/EXIF policy | Xong nền | `image_picker` dùng `imageQuality: 86`, `maxWidth: 1920`; EXIF/privacy policy nâng sâu còn P1 |
| M6.4 Upload queue/progress | Xong foundation | `MessageAttachmentUploadItem`, retry/remove, trạng thái queued/uploading/uploaded/failed/attached trong composer |
| M6.5 Attach file vào message | Xong foundation | `MessageAttachmentRemoteDataSource` upload `/files`, attach `/messages/{message_id}/attachments`, controller gắn file sau khi gửi message |
| M6.6 Attachment render trong timeline | Xong foundation | `ChatMessage.attachments`, REST/realtime parser, `_MessageAttachmentList` hiển thị tên file/kích thước dưới bubble |
| M6.7 Download/open/share | Chưa làm native | Đã giữ `downloadPath`; cần viewer/open intent/share scoped storage |
| M6.8 Voice recorder/player | Chưa làm native | Cần plugin record/playback, permission mic và waveform/timer |
| M6.9 Video/gallery viewer | Chưa làm native | Cần viewer ảnh/video, zoom/swipe/fullscreen/cache |
| M6.10 Call domain model | Xong foundation | `CallSession`, `CallMode`, `CallStatus`, `CallSignal` |
| M6.11 Call signaling repository | Xong REST foundation | `CallRemoteDataSource`, `CallRepositoryImpl`, start/get/accept/reject/cancel/hangup/signal use cases |
| M6.12 Outgoing call UX | Xong foundation | Header phone/video mở bottom sheet nhập `target_user_id` và gọi `StartCallUseCase` |
| M6.13 Incoming/active call/WebRTC | Chưa làm native | Cần WebSocket call events, incoming screen, `flutter_webrtc`, camera/mic controls và push bridge |

## Checklist M7

| Task | Trạng thái | Evidence |
|---|---|---|
| M7.1 Firebase project/flavor config | Xong foundation | `FirebaseRuntimeOptions` đọc Dart define theo platform; `bootstrap` cấu hình background handler |
| M7.2 Register/update/unregister push token | Xong foundation | `PushNotificationService.registerForWorkspace`, token refresh update, `unregister` khi logout |
| M7.3 Backend notification worker FCM/APNs | Backend-owned | Mobile đã có contract client; worker/delivery log thuộc backend |
| M7.4 Foreground notification handling | Xong foundation | `PushNotificationService.foregroundTargets`, HomeShell refresh notification center và hiển thị SnackBar mở nhanh |
| M7.5 Background/terminated notification | Xong foundation | `FirebaseMessaging.onBackgroundMessage`, `onMessageOpenedApp`, `getInitialMessage` parse target |
| M7.6 Badge count | Xong foundation | HomeShell bell badge lấy `unreadCount` từ `NotificationCenterController` |
| M7.7 Deep link/app link target | Xong foundation | `NotificationTarget` parse `workspace_id/channel_id/message_id`, route mở chat và highlight message nếu có trong timeline |
| M7.8 Notification preference/mute | Xong foundation | `NotificationPreference`, settings sync `/api/v1/notifications/preferences` |
| M7.9 Sensitive preview policy | Xong foundation | `AppSettings.sensitivePreviewEnabled` map sang preference `preview=false` |
| M7.10 Duplicate suppression | Xong foundation | Push service suppress theo `event_id`/`notification_id`/message id |

## Verification

| Kiểm tra | Trạng thái |
|---|---|
| `dart format` cho file thay đổi | Đã chạy, pass |
| `flutter analyze` | Đã chạy, `No issues found!` |
| `flutter test` | Đã chạy, 34 tests passed |

## M5 polish đã xử lý

- Forward dùng bottom sheet chọn kênh từ API thay cho nhập raw `channel_id`.
- Reaction dùng palette nhiều emoji và vẫn giữ toggle theo `reactedByMe`.
- Bubble render mention/markdown nhẹ bằng rich text tương thích ngược với component cũ.
- Thread có composer riêng ngay trong panel, gửi bằng `parent_id` và merge lại state cục bộ.
- Search có chip kết quả và jump-to-message, đồng thời message được highlight ngắn khi mở từ kết quả.
- Pin có thanh ghim nhanh trong room để nhảy tới tin ghim thay vì chỉ nằm trong quick action.
- Action bar dưới từng bubble đã được rút gọn thành long-press bottom sheet để timeline giống app chat native hơn.

M6 đã bắt đầu ở mức foundation. Các việc còn lại của M6 nằm ở native plugin/WebRTC: file picker đầy đủ, voice record/play, viewer/download/share, incoming call, active audio/video call và push bridge.

M7 đã khóa mobile foundation. Phần còn lại cần smoke test trên thiết bị thật với Firebase project thật, local notification native plugin nếu muốn hiện native banner foreground, Android/iOS app link verification và backend worker delivery log.

M8 đã khóa mobile foundation với offline cache, outbox/idempotent retry, sync catch-up, clear cache policy và network banner. Phần còn lại là chaos test bằng backend thật.

M9 đã có tab Nghiệp vụ bằng endpoint thật, gồm test/publish flow, tạo/đổi trạng thái ticket, API token list/revoke, audit log, admin health và run/pause/resume cronjob. Các thao tác ticket comment/attachment, rollback flow, announcement/system message, admin browser link và super-admin cần backend/API hoặc smoke test quyền/dữ liệu thật trước khi gọi là parity production.

M10 đã có foundation trong code: attachment permission rationale, chat suspend/reconnect khi app vào nền/resume, reduced-motion cho scroll/highlight, semantics label cho message và Settings version gate dùng endpoint mobile releases. Cần kiểm thử thêm trên thiết bị thật với TalkBack/VoiceOver, font lớn, rotation/tablet, timeline rất lớn, gallery nhiều ảnh và update policy bắt buộc.

M11 đã có foundation trong code/CI/docs: workflow mobile validate + signed release artifact, Android signing không dùng debug key cho release, test release policy/deep-link security, integration smoke test, checksum/manifest, tài liệu phân phối nội bộ và kế hoạch Android direct download. Cần môi trường thật để xác nhận GitHub secret, Firebase/Play Internal upload, thiết bị vật lý và publish manifest/download host.

M12 đã có Android-first download foundation: Play Console doc, privacy policy draft, download page spec, source static page ở `portal/download/`, download host manifest example và `tool/check_mobile_release.dart` để CI bắt thiếu sót release. Trước mắt phát Android qua APK signed tại `chat.vpsttt.com/download/`; CH Play chuyển sang sau bằng `store_url` trong manifest. Cần thao tác ngoài repo để tạo Play Console app, enroll Play App Signing, public privacy/support URL, upload AAB lên Internal/Closed track, chạy Pre-launch report và triển khai path tải thật.

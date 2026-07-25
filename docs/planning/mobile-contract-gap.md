# Mobile Contract Gap - Phase M0

Ngày cập nhật: 2026-07-15

Tài liệu này hoàn thành phần phân tích Phase M0 cho mobile app Flutter WebTui Chat. Phạm vi chỉ là contract, parity, readiness và backlog backend. Chưa triển khai Flutter UI, chưa tạo endpoint giả và chưa coi endpoint đề xuất là đã tồn tại.

## 1. Nguồn đã đối chiếu

| Nguồn | Vai trò |
|---|---|
| `docs/planning/mobile-flutter-roadmap.md` | Nguồn yêu cầu M0-M13, Clean Architecture mobile, Android/iOS release |
| `.agents/webtui-chat-mobile/SKILL.md` | Ràng buộc Flutter, UI Zalo-like, workspace scope, tiếng Việt có dấu |
| `docs/design/mobile/references/mobile-ui-reference.md` | Quy chuẩn UI mobile khi sang phase giao diện |
| `.agents/webtui-chat-architecture/SKILL.md` | Ràng buộc Clean Architecture và backend owner |
| `CleanArchitecture.md` | Kiến trúc tổng thể backend/frontend/mobile |
| `docs/architecture/source-layout.md` | Bố cục source và module backend |
| `docs/architecture/backend-clean-architecture.md` | Ranh giới domain/application/infrastructure/delivery |
| `backend/api/openapi/openapi.yaml` | Contract REST đang công bố |
| `backend/internal/**/delivery/http/handler.go` | Route Go thực tế, là nguồn sự thật tạm thời khi lệch OpenAPI |
| `frontend/apps/web/src/features/chat/**` | Parity chức năng web hiện tại |

Ảnh reference UI đã tồn tại tại `docs/design/mobile/references/webtui-mobile-zalo-reference.png`, nên không còn blocker cho phần UI ở phase sau. Phase M0 vẫn không dựng UI.

## 2. Kết luận nhanh M0

- Repo chưa có Flutter project `mobile/`, chưa có `pubspec.yaml` hoặc file Dart.
- OpenAPI đã có nền cho auth, user, workspace, RBAC, channel, message, file, notification, presence, direct conversation, ticket, bot, webhook, cronjob, audit, backup và desktop release.
- Go route có thêm một số route chưa được ghi đủ trong OpenAPI: contacts/contact requests, channel members, join requests, private session, message pins, một số update/delete user, admin channels/messages, webhook patch/delete/test và order bot.
- Message idempotency đã có nền thật: `SendMessageRequest.client_message_id`, header `Idempotency-Key`, unique index `messages_client_message_id_idx` và lookup theo `(workspace_id, channel_id, sender_id, client_message_id)`.
- Notification preference đã có nền theo user/workspace: mode `all|mentions|muted`, preview, quiet hours. Mobile vẫn cần device-scoped preference và push token lifecycle.
- Call hiện có là WebSocket signaling nhẹ (`CallOffer`, `CallAnswer`, `CallIceCandidate`, `CallRejected`, `CallEnded`) cộng message event dạng call. Chưa có call session API bền vững, ringing push, timeout worker, missed/ended call authority ở backend.
- Chưa có sync/catch-up cursor chuẩn cho mobile sau background/offline dài.
- Chưa có `push_devices` hoặc FCM/APNs registration API.
- Chưa có mobile release metadata/version gate. Hiện backend chỉ có version và desktop updater manifest.
- Bot hiện có catalog/installation/message cơ bản và route `order-bot` riêng. Mobile không được hard-code flow order VPSTTT; cần bot/AI config/flow/tool/knowledge theo workspace.

## 3. Ma trận parity web -> mobile

| Nhóm | Web hiện có | Mobile cần đạt | Contract hiện tại | Gap/owner |
|---|---|---|---|---|
| Auth/session | Login, Google login, refresh, logout, session list/revoke | Login, refresh tự động, session list/revoke, logout sạch device | OpenAPI và Go route đã có | P0: liên kết logout với unregister push device. Owner: `auth`, `mobile_devices` |
| User/profile | Hồ sơ user, cập nhật hồ sơ | Hồ sơ, avatar, thiết bị đăng nhập | OpenAPI có `users/me`; Go route có thêm update/delete user | P1: rà đủ update/delete trong OpenAPI. Owner: `users` |
| Workspace | List mine, get/update/create, member, settings, invite | Chọn workspace, switch tenant, cache tách theo workspace | Có nền tốt | P0: mọi payload push/deep link/sync phải mang workspace context |
| RBAC | Permission gate web | Ẩn/hiện màn theo permission, backend vẫn quyết định cuối | Có permissions, roles, check, member roles | P0: mobile cần manifest permission theo màn hình, không tự suy đoán |
| Contacts/danh bạ | Contacts, contact requests, accept/reject/cancel | Danh bạ, gửi lời mời, tạo DM theo contact | Go route có, OpenAPI chưa có | P0 cho parity danh bạ. Owner: `contacts` |
| Channel list | List/create/update/archive, members, join request | Kênh & Bot, trạng thái đã tham gia/chưa tham gia, xin tham gia/mở kênh | OpenAPI thiếu members/join/private-session | P0: bổ sung OpenAPI cho route Go đã có. Owner: `channels` |
| Direct conversation | Tạo/list DM | DM riêng, avatar, unread, deep link | OpenAPI có list/create | P0: cần cache/unread/sync cursor đi kèm |
| Message timeline | Text, reply, thread, edit, delete, reaction, forward, pin, call event | Timeline mobile, outbox, retry, reaction, pin, call cards | OpenAPI thiếu pins; send đã có idempotency | P0: bổ sung pins vào OpenAPI, chuẩn hóa idempotency/outbox |
| Unread/read state | Read state theo channel, badge web | Badge giống Zalo, mark read khi mở phòng, sync nhiều thiết bị | Có `read-state` | P0: sync cursor và unread event để mobile không lệch badge |
| Search | Search message | Search trong workspace/channel | OpenAPI có | P1: mobile UX search local + remote sau M5 |
| File/media | Upload, attachment, download, file versions, gallery bên phải | Camera/gallery/file/voice, preview, download, share intent | OpenAPI có nền | P1: upload resume/chunk cho mạng mobile yếu |
| Notification | List, mark read, preference cơ bản | Push foreground/background/terminated, badge, mute, quiet hours, lock-screen preview | Preference có; push devices thiếu | P0: `push_devices`, FCM/APNs worker, delivery log |
| Presence/typing | Presence heartbeat, WS typing | Online/away/offline, typing, lifecycle background | Có presence, WS typing | P0: device identity dùng chung với mobile device registry |
| Realtime | WS event cho message/contact/pin/call nhẹ | Reconnect, resubscribe, catch-up không mất event | WS có, cursor thiếu | P0: event envelope và sync/catch-up API |
| Audio/video call | WebRTC call trong web, call card | Incoming ringing, accept/reject, missed/ended card, reconnect, push khi app nền | WS signal nhẹ; chưa có call API | P0: call session/signaling backend có owner rõ |
| Bot/AI | Bot catalog, install, send, order bot panel riêng | Bot theo workspace, provider/model/flow/tool/knowledge/test/audit | Bot cơ bản có; AI flow thiếu | P0: bot/AI config không hard-code VPSTTT. Owner: `bots`, `ai_runtime` |
| Ticket | List/create/update ticket | Ticket list/detail/lifecycle tiếng Việt có dấu | OpenAPI có CRUD cơ bản | P1: comment, assignment history, attachment, notification nếu cần full lifecycle |
| Automation/webhook/API token | Cronjob, webhook, API token web/admin | Mobile admin-friendly, có thể mở web admin cho tác vụ nặng | OpenAPI có một phần; Go có patch/delete/test thêm | P1: bổ sung OpenAPI và permission gate |
| Admin workspace | Stats/health, một số route admin | Workspace admin quản lý cơ bản trên mobile | OpenAPI thiếu admin channels/messages | P1: mobile admin tối giản, không ép đầy đủ web admin |
| Super admin | Sản phẩm có super admin toàn hệ thống | List workspace, trạng thái, nhảy workspace theo quyền | Chưa thấy contract riêng | P1: super admin workspace API |
| Release/download | Desktop release metadata | Mobile version gate, CH Play/APK/TestFlight link | Chỉ desktop release | P0: mobile release metadata |
| Privacy/security | Web cache/offline nhẹ | Secure storage, cache retention, log redaction, push privacy | Chưa có policy API đầy đủ | P0: privacy/data retention đã chốt ở tài liệu này |

## 4. Đối chiếu OpenAPI với route Go

Khi OpenAPI lệch route Go, route Go là nguồn sự thật tạm thời. Các gap dưới đây không phải endpoint mới đã tồn tại trong contract; đây là phần cần backend owner bổ sung hoặc xác nhận.

### 4.1. Route đã có trong Go nhưng OpenAPI thiếu hoặc chưa đủ

| Nhóm | Route Go | Tác động mobile | Ưu tiên |
|---|---|---|---|
| Contacts | `GET /api/v1/contacts`, `GET/POST /api/v1/contact-requests`, accept/reject/cancel | Mobile cần danh bạ và DM theo contact | P0 |
| Channel members | `GET/POST /workspaces/:workspace_id/channels/:channel_id/members`, `PATCH .../members/:user_id` | Màn member, quyền mở kênh, trạng thái tham gia | P0 |
| Channel join request | `POST/GET /channels/:channel_id/join-requests`, approve/reject | Fix luồng "chưa tham gia thì bấm tham gia" | P0 |
| Private session | `POST /channels/:channel_id/private-session` | Mở làm việc riêng tư theo channel/bot | P1 |
| Message pins | `GET /channels/:channel_id/pins`, `POST/DELETE /messages/:message_id/pin` | Tab "Đã ghim" và pin/unpin trong chat | P0 |
| User admin | `PATCH /api/v1/users/:user_id`, `DELETE /api/v1/users/:user_id` | Mobile admin nếu bật quản lý user | P1 |
| Workspace settings list | `GET /workspaces/:workspace_id/settings` | Mobile settings cần đọc toàn bộ setting workspace | P1 |
| Admin detail | `GET /workspaces/:workspace_id/admin/channels`, `GET /admin/messages` | Mobile admin dashboard tối giản | P1 |
| Webhook management | `PATCH/DELETE incoming-webhooks`, `PATCH/DELETE outgoing-webhooks`, `POST outgoing-webhooks/:id/test` | Mobile admin/webhook nếu làm parity sâu | P1 |
| Order bot | `/workspaces/:workspace_id/order-bot/**` | Không dùng làm contract AI chung cho mobile | Không dùng làm P0 mobile |

### 4.2. OpenAPI đã có nhưng cần làm rõ cho mobile

| Nhóm | Hiện trạng | Việc cần chốt |
|---|---|---|
| Message send | Có `client_message_id`; route Go cũng đọc header `Idempotency-Key` | Chuẩn hóa thành yêu cầu P0 cho mọi outbox send/retry |
| Notification preference | Có mode, preview, quiet hours theo workspace | Cần device override, call ringing preference, badge policy |
| Presence heartbeat | Có `device_id` trong presence | Không dùng presence thay cho push device registry vì lifecycle khác nhau |
| Desktop release | Có `/version` và `/desktop/releases/{channel}/{target}/{arch}/{current_version}` | Thêm metadata riêng cho mobile platform/channel |
| Ticket | CRUD cơ bản | Nếu mobile cần lifecycle đầy đủ phải thêm comment/attachment/audit/assignment event |
| Bot | Catalog/install/send message | Thiếu provider/model/flow/tool/knowledge/test/audit/version |

### 4.3. Endpoint chưa có cho mobile P0/P1

| Ưu tiên | Nhóm | Contract cần có | Backend owner đề xuất | Ghi chú |
|---|---|---|---|---|
| P0 | Push device registry | Register/update/unregister/list device token | `notifications` hoặc module mới `mobile_devices` | Không trộn với `user_sessions` hoặc `presence` |
| P0 | Notification worker | FCM/APNs job, retry, delivery log, duplicate suppression | `notifications`, `worker` | Push payload không chứa secret/nội dung nhạy cảm nếu preview tắt |
| P0 | Sync/catch-up | Workspace event cursor API | Module mới `sync` hoặc `outbox` mở rộng | Bắt buộc cho offline/background |
| P0 | Call session/signaling | Call create/invite/accept/reject/cancel/hangup + ICE/SDP events | Module mới `calls` | WS signal hiện tại chưa đủ cho mobile app nền |
| P0 | Call push/timeout | Ringing push, timeout worker, missed call system message | `calls`, `notifications`, `worker`, `messages` | Đảm bảo bên kia thấy cuộc gọi đến |
| P0 | Bot/AI workspace config | Provider/model/secret reference, flow, tool, knowledge, test, audit | `bots`, `ai_runtime`, `vault` | Mobile không nhận secret plaintext |
| P0 | Mobile release metadata | Latest/minimum/recommended version, store/APK/TestFlight link, checksum | `health` hoặc `releases` | Phục vụ M10/M11/M12 |
| P0 | Idempotency chuẩn | `Idempotency-Key` và client ID cho message/file/call mutations | Từng module owner | Message đã có, cần thống nhất cho file/call |
| P1 | Upload resume/chunk | Multipart/chunk session, checksum, resume token | `files` | Cần cho file lớn trên mạng yếu |
| P1 | Super admin workspace API | List/search workspace, health, switch context theo quyền | `admin` hoặc `super_admin` | Không trộn dữ liệu tenant |
| P1 | Account deletion/export | Export data, request delete, status | `users`, `privacy` | Cần cho store nếu public rộng |
| P1 | Webhook/API token parity | Patch/delete/test đầy đủ trong OpenAPI | `webhooks`, `api_tokens` | Chủ yếu cho admin mobile |
| P1 | Ticket lifecycle đầy đủ | Comment, attachment, assignment history, status event | `tickets`, `files`, `notifications` | CRUD hiện tại chưa đủ nếu mobile thay web ticket |

## 5. Thiết kế idempotency cho message/outbox

### 5.1. Trạng thái hiện có

- Client gửi `client_message_id` trong body hoặc `Idempotency-Key` trong header.
- Backend đưa `client_message_id` vào `metadata.client_message_id`.
- PostgreSQL có unique index `messages_client_message_id_idx` theo `workspace_id`, `channel_id`, `sender_id`, `metadata ->> 'client_message_id'`.
- Repository kiểm tra message cũ trước khi insert và trả lại message đã tạo nếu retry trùng.

### 5.2. Quy ước cho mobile

| Quy tắc | Thiết kế |
|---|---|
| ID phía client | Mobile tạo UUID v7 hoặc ULID cho `client_message_id` ngay khi đưa message vào outbox |
| Header | Mọi mutation có retry gửi thêm `Idempotency-Key: <client_operation_id>` |
| Message text | Body dùng `client_message_id` giống hiện tại |
| Attachment | Mỗi file trong queue có `client_attachment_id`; mutation attach dùng `Idempotency-Key` riêng |
| Call event | Missed/ended call card dùng `client_message_id = call-<call_id>-<status>` hoặc id operation tương đương |
| Scope unique | Không dùng global key; scope tối thiểu là `workspace_id + user_id + operation_id`, riêng message hiện đang là `workspace_id + channel_id + sender_id + client_message_id` |
| Response retry | Nếu duplicate hợp lệ, backend trả entity đã tạo, không trả lỗi 409 |
| Outbox mobile | Trạng thái local: `draft`, `queued`, `sending`, `sent`, `failed`, `cancelled` |
| Redaction | Log không chứa body message, file path local, token hoặc nội dung push |

### 5.3. Gap còn lại

- OpenAPI nên ghi rõ `Idempotency-Key` trên `POST /messages`, `POST /attachments`, `POST /files`, call mutations và các action có retry.
- File upload/attach hiện chưa có idempotency rõ như message.
- Forward message có header trong OpenAPI nhưng Go route chưa truyền header vào service forward. Cần xác nhận có cần idempotent forward trên mobile hay không.

## 6. Thiết kế sync/catch-up cursor

Mobile không thể chỉ dựa vào WebSocket vì app có thể bị background, mất mạng hoặc bị OS kill. Cần một contract catch-up từ backend.

### 6.1. Endpoint đề xuất cần backend owner phê duyệt

| Method | Path | Mục đích |
|---|---|---|
| `GET` | `/api/v1/workspaces/{workspace_id}/sync?cursor=&limit=` | Lấy event sau cursor |
| `POST` | `/api/v1/workspaces/{workspace_id}/sync/ack` | Ghi nhận cursor cuối client đã xử lý, tùy chọn |
| `GET` | `/api/v1/workspaces/{workspace_id}/sync/bootstrap` | Snapshot nhẹ khi client chưa có cursor hoặc cursor quá cũ |

### 6.2. Event envelope

```json
{
  "event_id": "uuid",
  "sequence": 123456,
  "workspace_id": "uuid",
  "type": "message.created",
  "occurred_at": "2026-07-15T09:00:00Z",
  "actor_user_id": "uuid",
  "channel_id": "uuid",
  "aggregate_type": "message",
  "aggregate_id": "uuid",
  "payload": {}
}
```

### 6.3. Quy tắc cursor

- Cursor monotonic theo `workspace_id`; không dùng cursor chung toàn hệ thống cho mobile.
- Server trả `events`, `next_cursor`, `has_more`, `server_time`.
- Nếu cursor quá cũ hoặc bị prune, server trả mã lỗi có thể khôi phục, ví dụ `SYNC_CURSOR_EXPIRED`, kèm hướng dẫn gọi bootstrap.
- Client reducer phải idempotent theo `event_id`.
- Event quan trọng cần có: message created/updated/deleted, reaction added/removed, pin/unpin, read state changed, channel updated, member changed, direct created, notification created/read, presence summarized, contact changed, call created/updated/ended.
- WebSocket chỉ đánh thức UI realtime; REST sync là nguồn khôi phục sau reconnect.

## 7. Thiết kế device registration và notification preference

### 7.1. Device registration P0

Endpoint dưới đây là đề xuất contract, chưa tồn tại và cần owner backend.

| Method | Path | Mục đích |
|---|---|---|
| `POST` | `/api/v1/mobile/devices` | Đăng ký device và push token |
| `PATCH` | `/api/v1/mobile/devices/{device_id}` | Cập nhật push token, app version, permission |
| `DELETE` | `/api/v1/mobile/devices/{device_id}` | Unregister khi logout hoặc user tắt thiết bị |
| `GET` | `/api/v1/mobile/devices` | User xem danh sách thiết bị nhận thông báo |

Schema tối thiểu:

| Field | Ghi chú |
|---|---|
| `device_id` | ID ổn định do app sinh, không phải FCM token |
| `platform` | `android`, `ios` |
| `push_provider` | `fcm`, `apns` nếu cần |
| `push_token` | Lưu server-side, không log plaintext |
| `app_version`, `build_number`, `release_channel` | Dùng debug release issue |
| `locale`, `timezone` | Dùng quiet hours và nội dung push |
| `notification_permission` | `granted`, `denied`, `provisional`, `unknown` |
| `last_seen_at` | Hỗ trợ cleanup device cũ |

### 7.2. Notification preference

Hiện có preference theo `user_id + workspace_id`. Mobile cần mở rộng chính sách:

| Mức | Quy tắc |
|---|---|
| Workspace | `all`, `mentions`, `muted`, preview on/off, quiet hours |
| Channel/DM | Mute riêng, mentions only, duration mute nếu cần |
| Device | Bật/tắt trên thiết bị này, sound/vibrate/call ringing |
| Privacy | Lock-screen preview có thể ẩn tên/nội dung; push payload vẫn có deep link target |
| Badge | Badge count lấy từ unread server, không tự cộng trừ mù khi app nền |

Push payload tối thiểu phải có `workspace_id`, `target_type`, `channel_id` hoặc `conversation_id`, `message_id` nếu có, `event_id`, `notification_id`, `deep_link`. Nếu preview tắt, payload không chứa nội dung message.

## 8. Thiết kế call signaling cho mobile

### 8.1. Hiện trạng

- Web dùng WebRTC peer-to-peer.
- WebSocket nhận/gửi `CallOffer`, `CallAnswer`, `CallIceCandidate`, `CallRejected`, `CallEnded`.
- Web ghi call card bằng message kind `event` và metadata `message_type=call`.
- Chưa có call session lưu ở backend, chưa có ringing push, timeout worker và trạng thái authoritative.

### 8.2. Contract P0 cần có

| Method | Path | Mục đích |
|---|---|---|
| `POST` | `/api/v1/workspaces/{workspace_id}/calls` | Tạo cuộc gọi và mời người nhận |
| `POST` | `/api/v1/workspaces/{workspace_id}/calls/{call_id}/accept` | Chấp nhận |
| `POST` | `/api/v1/workspaces/{workspace_id}/calls/{call_id}/reject` | Từ chối |
| `POST` | `/api/v1/workspaces/{workspace_id}/calls/{call_id}/cancel` | Người gọi hủy khi chưa bắt máy |
| `POST` | `/api/v1/workspaces/{workspace_id}/calls/{call_id}/hangup` | Kết thúc khi đang gọi |
| `POST` | `/api/v1/workspaces/{workspace_id}/calls/{call_id}/offer` | Gửi SDP offer nếu vẫn dùng REST fallback |
| `POST` | `/api/v1/workspaces/{workspace_id}/calls/{call_id}/answer` | Gửi SDP answer |
| `POST` | `/api/v1/workspaces/{workspace_id}/calls/{call_id}/ice-candidates` | Gửi ICE candidate |

Event realtime/push:

- `call.invited`
- `call.ringing`
- `call.accepted`
- `call.rejected`
- `call.cancelled`
- `call.ended`
- `call.missed`
- `call.offer`
- `call.answer`
- `call.ice_candidate`

Backend phải là nơi quyết định khi nào tạo "Bạn bị nhỡ" hoặc "Cuộc gọi thoại đến 0 phút 6 giây" để web/mobile/desktop đồng bộ giống nhau.

## 9. Bot/AI theo từng workspace

Mobile không gọi trực tiếp LLM provider và không chứa secret AI. API order VPSTTT chỉ được xem là một tool cụ thể, không phải contract bot chung.

| Nhóm | Contract cần có | Ưu tiên |
|---|---|---|
| Bot catalog | List/create/update bot, status active/inactive, avatar, channel binding | P0 |
| Installation | Install/uninstall/update config theo channel/workspace | P0 |
| AI provider | Provider/model config, secret reference, không trả secret plaintext | P0 |
| Flow | Flow draft/publish/rollback/version, trigger, prompt, fallback, handoff | P0 |
| Tool registry | Danh sách tool theo workspace, input schema, permission, timeout | P0 |
| Knowledge | Knowledge source, sync status, scope workspace | P1 |
| Test run | Chạy thử flow với input mẫu, transcript, tool call, lỗi | P0 |
| Audit | Ai sửa, lúc nào, version nào, thay đổi gì | P1 |

## 10. Android-first device matrix

M0 chốt Android-first để M11/M12 có hướng rõ. iOS vẫn giữ trong roadmap nhưng không chặn Android MVP.

| Nhóm thiết bị | Mục tiêu test | Ghi chú |
|---|---|---|
| Android 10, 3-4 GB RAM, màn 720p | Thiết bị thấp | Kiểm tra timeline, ảnh, push, app resume |
| Android 12/13, 4-6 GB RAM, màn 1080p | Thiết bị phổ biến | Target chính cho MVP |
| Android 14/15, 8 GB RAM, màn cao | Thiết bị mới | Permission notification, media picker, background policy |
| Tablet Android 10 inch | P1 | Split view nếu làm sau |
| iOS 16+ iPhone | Sau Android MVP | TestFlight ở M13 |

Quyết định M0:

- Android là nền tảng phát hành trước.
- `applicationId` production cần chốt ở M1 và không đổi sau khi đưa lên Play Console.
- Target SDK/API phải kiểm tra lại trước release vì Google cập nhật hằng năm.
- Build nội bộ dùng Firebase App Distribution và APK signed trên `chat.vpsttt.com/download/`; CH Play làm ở M12.

## 11. Privacy và data retention

| Mảng | Quyết định M0 |
|---|---|
| Token | Access token ở memory; refresh token trong secure storage; logout/revoke phải xóa token và unregister push device |
| Cache chat | Local cache scope theo `workspace_id`; không trộn workspace/user |
| Outbox/draft | Giữ đến khi gửi thành công hoặc user xóa; không bị clear cache thường xóa nhầm |
| File cache | Có TTL hoặc dung lượng tối đa; file tải về cần hiển thị rõ trên thiết bị |
| Push payload | Không chứa secret; tôn trọng preview off và quiet hours |
| Crash/log | Không log nội dung message, Authorization header, refresh token, push token, file local path |
| Account data | Nếu public store, cần chính sách export/delete và endpoint hỗ trợ |
| AI/bot | Không lưu hoặc hiển thị secret provider trên mobile; audit action admin |
| Telemetry | Chỉ gửi metadata kỹ thuật đã redaction; không gửi nội dung chat/ticket |

## 12. Acceptance criteria cho Phase M0

Phase M0 được xem là hoàn thành ở mức planning/contract readiness khi:

- Có ma trận parity web -> mobile và phân loại P0/P1.
- Có bảng đối chiếu OpenAPI với route Go, ghi rõ route Go là nguồn sự thật tạm thời khi lệch.
- Có danh sách endpoint/API cần bổ sung cho mobile theo P0/P1, có owner backend đề xuất.
- Có thiết kế idempotency/outbox cho message và hướng mở rộng sang file/call.
- Có thiết kế sync/catch-up cursor.
- Có thiết kế device registration và notification preference.
- Có contract direction cho call signaling mobile, bao gồm push/ringing/missed/ended call.
- Có hướng bot/AI theo workspace, không hard-code API order VPSTTT.
- Có Android-first device matrix.
- Có privacy/data retention policy tối thiểu.
- Không triển khai Flutter UI, không tạo endpoint giả và không ghi endpoint đề xuất như đã có.

Các task M0.4 và M0.5 trong roadmap (`Sinh Dart client tự động`, `Contract test trong CI`) chưa thể chạy vì Flutter project chưa tồn tại và OpenAPI còn gap P0. Chúng được chuyển thành điều kiện khởi động M1: sau khi backend owner chốt P0 contract, mới scaffold mobile và sinh client.

## 13. Backlog API cần bổ sung

### P0

| ID | API/contract | Lý do |
|---|---|---|
| M0-P0-01 | Bổ sung OpenAPI cho contacts/contact requests | Mobile cần danh bạ và tạo DM đúng parity |
| M0-P0-02 | Bổ sung OpenAPI cho channel members/join requests | Fix luồng chưa tham gia kênh |
| M0-P0-03 | Bổ sung OpenAPI cho message pins | Tab đã ghim và pin/unpin message |
| M0-P0-04 | Chuẩn hóa `Idempotency-Key` trên message/file/call mutations | Offline retry không nhân bản dữ liệu |
| M0-P0-05 | `push_devices` register/update/unregister/list | Push token lifecycle |
| M0-P0-06 | FCM/APNs worker, delivery log, duplicate suppression | Push production ổn định |
| M0-P0-07 | Notification preference mở rộng theo device/channel/call | Mute/quiet hours/preview/ringing đúng |
| M0-P0-08 | Sync/catch-up cursor API | Không mất event sau background/offline |
| M0-P0-09 | Call session/signaling API | Mobile video/audio call thật, bên kia thấy incoming call |
| M0-P0-10 | Call timeout/missed/ended system message authority | Hiển thị call card nhất quán web/mobile/desktop |
| M0-P0-11 | Bot/AI provider/model/flow/tool/test config theo workspace | Mỗi công ty có flow bot riêng |
| M0-P0-12 | Mobile release metadata/version API | Version gate, CH Play/APK/TestFlight link |

### P1

| ID | API/contract | Lý do |
|---|---|---|
| M0-P1-01 | Upload resume/chunk và checksum | File lớn, mạng yếu |
| M0-P1-02 | Super admin workspace API | Quản lý toàn bộ workspace trên mobile nếu cần |
| M0-P1-03 | OpenAPI cho webhook patch/delete/test và admin channels/messages | Parity admin sâu |
| M0-P1-04 | Ticket comment/attachment/audit/assignment event | Ticket lifecycle đầy đủ |
| M0-P1-05 | Account export/delete API | Store privacy nếu public rộng |
| M0-P1-06 | Managed/private app metadata | B2B workspace qua Managed Google Play |

## 14. Việc tiếp theo sau M0

1. Backend owner xác nhận P0 contract nào làm trước, đặc biệt push device, sync cursor, call session và bot/AI config.
2. Cập nhật OpenAPI cho các route Go đã có nhưng bị thiếu trước khi sinh Dart client.
3. Sau khi P0 contract tối thiểu ổn định, bắt đầu M1 scaffold `mobile/` Flutter theo Clean Architecture.
4. Trong M1, tạo CI mobile và chỉ sinh Dart client từ contract đã chốt, không viết tay DTO trùng lặp.

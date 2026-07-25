# Hội thoại và kênh mobile

Phase M4 triển khai feature-first Clean Architecture cho màn Tin nhắn, Danh bạ, Kênh và phòng chat.

## Ranh giới

- `domain`: `ConversationSummary`, `ChatMessage`, `ChannelMember`, `ChannelFile`, repository contract.
- `application`: load home, mở direct conversation không tạo trùng, tạo/join/invite kênh, load timeline, gửi tin, mark read, lưu draft.
- `data`: REST data source qua `ApiTransport`, mapper DTO nội bộ, draft local qua `AppDatabase` key-value scoped theo `workspace:{id}:drafts`.
- `presentation`: controller Riverpod và screen/widget Flutter. Widget không import Dio, Drift, secure storage, Firebase hoặc DTO.

## API đang dùng

- `GET/POST /api/v1/workspaces/{workspace_id}/direct-conversations`
- `GET/POST /api/v1/workspaces/{workspace_id}/channels`
- `GET /api/v1/workspaces/{workspace_id}/channels/{channel_id}`
- `GET/POST /api/v1/workspaces/{workspace_id}/channels/{channel_id}/members`
- `POST /api/v1/workspaces/{workspace_id}/channels/{channel_id}/join-requests`
- `GET/POST/DELETE /api/v1/workspaces/{workspace_id}/channels/{channel_id}/join-requests`
- `PUT /api/v1/workspaces/{workspace_id}/channels/{channel_id}/read-state`
- `GET/POST /api/v1/workspaces/{workspace_id}/channels/{channel_id}/messages`
- `GET /api/v1/workspaces/{workspace_id}/channels/{channel_id}/pins`
- `GET /api/v1/contacts`
- `GET /api/v1/workspaces/{workspace_id}/members`

## Blocker/TODO

- Backend hiện có `GET /api/v1/workspaces/{workspace_id}/files` theo workspace, chưa có filter media/file theo từng `channel_id`; tab Media/Tệp không dùng mock production và chỉ hiển thị empty/API-backed workspace files.
- Search conversation/user/channel đang lọc trên dữ liệu API đã tải. Khi backend có endpoint search conversation/channel riêng, chuyển controller sang use case search server-side.

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

## Ghi chú tích hợp

- Media/tệp theo kênh dùng API thật `GET /api/v1/workspaces/{workspace_id}/channels/{channel_id}/media` và các attachment endpoint theo channel/message.
- Tìm kiếm nhanh trong danh sách hiện tại chạy trên dữ liệu API đã tải; tìm kiếm nội dung đầy đủ dùng endpoint search phía server.

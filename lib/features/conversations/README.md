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
- Gửi tệp: tệp ≥ 8 MB tải từng phần qua `POST /files/uploads`, `PUT /files/uploads/{upload_id}/parts/{n}` (3 mảnh 5 MB
  cùng lúc, mảnh lỗi mạng thử lại), `POST /files/uploads/{upload_id}/complete`; tệp nhỏ hơn dùng `POST /files`.
- Video chọn từ mục Video được nén trên máy trước khi tải (kênh native `webtui/video_compress`): Android Media3
  Transformer (cạnh ngắn 720 px, H.264 ~2,5 Mbps, AAC 128 kbps); iOS `AVAssetExportSession` preset 1280x720 (không
  đặt được bitrate). Video < 4 MB, nén lỗi hoặc bản nén không nhỏ hơn 15 % thì gửi bản gốc; gửi qua mục Tệp luôn
  giữ bản gốc.
- "Nén + tải lên" chạy trong `MessageMediaUploader` dùng chung toàn app (không tải trùng một tệp, thoát phòng vẫn
  tải tiếp). Bấm Gửi khi tệp chưa tải xong: tin vào hàng chờ với `pending_uploads`, bộ gửi tin chờ tải nốt ở nền
  (không chặn tin chữ gửi sau) rồi mới gửi tin.
- Tìm kiếm nhanh trong danh sách hiện tại chạy trên dữ liệu API đã tải; tìm kiếm nội dung đầy đủ dùng endpoint search phía server.

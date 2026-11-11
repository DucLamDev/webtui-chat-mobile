# Trạng thái Mobile App Flutter

Ngày cập nhật: 2026-11-11

Bản ghi chi tiết theo từng phase M0-M12 trước đây đã lỗi thời và được thay bằng
tóm tắt này. Lịch sử thay đổi theo phiên bản nằm ở `CHANGELOG.md`; kế hoạch gốc
ở `docs/planning/mobile-flutter-roadmap.md` (tài liệu lưu trữ, không còn phản ánh
đầy đủ trạng thái hiện tại).

## Tính năng đã có trong app

| Nhóm | Trạng thái |
|---|---|
| Kết nối máy chủ tự host, đăng nhập, phiên, nhiều tài khoản | Có |
| Workspace, phân quyền, hồ sơ, cài đặt, khoá ứng dụng | Có |
| Hội thoại, kênh, tin nhắn realtime, tệp, ảnh, ghi âm, gửi video nhanh | Có |
| Gọi 1-1 âm thanh / video, CallKit và thông báo cuộc gọi Android | Có |
| Đăng nhập bằng mã QR, duyệt thiết bị mới | Có |
| Tin nhắn bí mật (mã hoá đầu cuối), My Note | Có |
| Biểu mẫu, biểu đồ, phê duyệt | Có |
| Hộp thư khách đa kênh | Có |
| Họp video LiveKit trong kênh | Có |
| Gọi cả nhóm có đổ chuông (nhận / từ chối, dừng chuông máy khác, hiện lại khi mở app) | Có |
| Push FCM / APNs, trung tâm thông báo, deep link | Có |
| Cache, hàng đợi gửi, đồng bộ lại sau khi mất mạng | Có |
| Phát hành Android (AAB, tuỳ chọn đẩy lên kênh thử nội bộ Google Play), iOS TestFlight | Có, xem tài liệu phát hành trong `docs/` |

## Kiểm tra

- `flutter analyze`, `flutter test`.
- Smoke test: `flutter test integration_test/app_smoke_test.dart -d flutter-tester`
  (không cần thiết bị; CI chạy trong job `verify`).

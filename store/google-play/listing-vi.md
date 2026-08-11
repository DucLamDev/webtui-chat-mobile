# Google Play Store Listing — vi-VN

Kiểm tra lại giới hạn ký tự ngay trong Play Console trước khi submit. Không thêm
tính năng chưa có trong artifact production.

## Tên ứng dụng

WebTUI Chat

## Mô tả ngắn

Nhắn tin, gọi và cộng tác an toàn cho đội nhóm trên máy chủ riêng.

## Mô tả đầy đủ

WebTUI Chat giúp đội nhóm trao đổi và làm việc trên máy chủ do tổ chức của bạn
quản lý. Chỉ cần nhập domain WebTUI Chat được quản trị viên cung cấp để đăng
nhập và bắt đầu cộng tác.

Tính năng chính:

• Nhắn tin trực tiếp và trao đổi trong kênh.
• Gửi ảnh, tệp và tin nhắn thoại do bạn chủ động chọn.
• Gọi thoại và gọi video khi máy chủ hỗ trợ.
• Theo dõi thông báo, phản ứng, ghim và tìm kiếm hội thoại.
• Làm việc với nhiệm vụ, lịch và bot theo cấu hình của tổ chức.
• Chặn người dùng, báo cáo tin nhắn hoặc tài khoản vi phạm.
• Quản lý phiên đăng nhập, quyền riêng tư và xóa tài khoản ngay trong ứng dụng.

Dữ liệu hội thoại được gửi tới instance WebTUI Chat mà bạn hoặc tổ chức lựa
chọn. Ứng dụng production yêu cầu HTTPS/WSS và lưu thông tin phiên dài hạn trong
kho bảo mật của hệ điều hành. WebTUI Chat không chứa quảng cáo và không đọc danh
bạ điện thoại của bạn.

Một số chức năng như cuộc gọi, thông báo nền, tệp, bot hoặc đăng nhập SSO phụ
thuộc cấu hình của từng máy chủ. Bạn cần tài khoản và domain instance đang hoạt
động; hãy liên hệ quản trị viên tổ chức nếu chưa có thông tin này.

## Ghi chú bản phát hành 1.0.0

• Hoàn thiện nhắn tin, kênh, tệp, thông báo và cuộc gọi cho mobile.
• Thêm báo cáo nội dung/người dùng, chặn và quản lý danh sách đã chặn.
• Thêm chấp thuận Điều khoản/Chính sách quyền riêng tư và xóa tài khoản.
• Tăng cường bảo mật release, App Links và khả năng tương thích Android 16.

## Asset mapping

- App icon: `webtui-chat-portal/store-assets/play/icon-512.png`.
- Feature graphic: `webtui-chat-portal/store-assets/play/feature-graphic-1024x500.png`.
- Phone screenshots: `webtui-chat-portal/store-assets/play/phone/`.
- Large-screen screenshots: chưa upload. Khi điền mục tablet/Chromebook, chụp
  tối thiểu bốn ảnh thật của đúng AAB, 1080–7680 px và tỷ lệ 9:16 hoặc 16:9.

Chỉ dùng ảnh sinh từ manifest deterministic đã pass `npm run assets:check`.

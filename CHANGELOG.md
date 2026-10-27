# Nhật ký thay đổi

Mỗi lần sửa (mỗi Pull Request): tăng VERSION (sửa lỗi → số cuối, tính năng → số giữa) và thêm đúng một mục mới ở đầu
danh sách, theo mẫu bên dưới. Hàng chờ gộp tự đổi sang số kế tiếp khi hai nhánh cùng lấy một số.

## 1.1.0 · 27/10/2026
### Tính năng
- Sửa gọi điện không có tiếng trên iPhone, thêm chuông, góp ý trong app và nhiều lỗi giao diện
  Cuộc gọi trên iPhone kết nối nhưng không nghe tiếng: app báo cho WebRTC khi CallKit bật âm thanh cuộc gọi. Gọi đi
  có chuông chờ đến lúc bên kia nhận máy; cuộc gọi đến khi đang mở app có nhạc chuông (kêu cả khi gạt im lặng) và rung.
  Danh bạ là mọi thành viên workspace, bấm là nhắn được ngay (không cần kết bạn), tìm bạn bè trong danh sách này. Thêm
  mục Cài đặt → Gửi góp ý. Sửa: hộp thoại Điều khoản hiện liên tục, tải ảnh đại diện không được, ô tìm kiếm không đóng
  được (chạm ra ngoài, kéo danh sách hoặc nút x để đóng). Bỏ chặn chụp / quay màn hình.

## 1.0.4 · 27/10/2026
### Sửa lỗi
- Sửa lỗi biên dịch phần nhận cuộc gọi đến trên iOS
  Đoạn hiện màn hình cuộc gọi đến (CallKit) truyền dữ liệu sai kiểu cho thư viện cuộc gọi nên Xcode không build được
  app. Đổi sang đúng kiểu thư viện yêu cầu, chức năng không đổi.

## 1.0.3 · 27/10/2026
### Sửa lỗi
- Sửa lỗi biên dịch Swift làm hỏng bước build iOS
  Đoạn xử lý liên kết mở app (universal link) lúc khởi động viết sai cú pháp Swift nên Xcode không đóng gói được app.
  Viết lại đúng cú pháp, chức năng không đổi.

## 1.0.2 · 27/10/2026
### Sửa lỗi
- App iOS yêu cầu iOS 15 trở lên để build được bản TestFlight
  Thư viện thông báo đẩy Firebase bản mới chỉ chạy trên iOS 15 trở lên nên bước build iOS trên GitHub báo lỗi. Nâng
  phiên bản iOS tối thiểu của app từ 13.0 lên 15.0 (iPhone 6s trở về sau vẫn cài được).

## 1.0.1 · 26/10/2026
### Sửa lỗi
- Sửa lỗi làm hỏng bước kiểm tra và build trên GitHub
  Bản 1.0.0 có đoạn test viết sai kiểu định dạng nên bước kiểm tra tự động dừng, không build được app. Bản này sửa
  lại để GitHub chạy tiếp các bước build Android / iOS. Máy build của GitHub nay mặc định dùng Java 25 làm Gradle báo
  lỗi khi build Android; workflow cài cố định Java 17 như dự án yêu cầu.

## 1.0.0 · 26/10/2026
### Tính năng
- Build iOS lên TestFlight bằng GitHub Actions; chức năng nội bộ VPSTTT chỉ có trên chat.vpsttt.com
  Gắn tag `mobile-vX.Y.Z` là GitHub tự build app iOS có ký và đẩy lên TestFlight (tuỳ chọn tự gửi duyệt App Store).
  Tab Automation và các kênh bot nội bộ chỉ hiện khi đăng nhập server chat.vpsttt.com; server khác (khách tự host)
  không có. Đây cũng là bản đầu tiên đánh số phiên bản: từ đây mỗi lần gộp ghi thay đổi ở tệp này.

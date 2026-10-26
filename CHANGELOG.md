# Nhật ký thay đổi

Mỗi lần sửa (mỗi Pull Request): tăng VERSION (sửa lỗi → số cuối, tính năng → số giữa) và thêm đúng một mục mới ở đầu
danh sách, theo mẫu bên dưới. Hàng chờ gộp tự đổi sang số kế tiếp khi hai nhánh cùng lấy một số.

## 1.0.0 · 26/10/2026
### Tính năng
- Build iOS lên TestFlight bằng GitHub Actions; chức năng nội bộ VPSTTT chỉ có trên chat.vpsttt.com
  Gắn tag `mobile-vX.Y.Z` là GitHub tự build app iOS có ký và đẩy lên TestFlight (tuỳ chọn tự gửi duyệt App Store).
  Tab Automation và các kênh bot nội bộ chỉ hiện khi đăng nhập server chat.vpsttt.com; server khác (khách tự host)
  không có. Đây cũng là bản đầu tiên đánh số phiên bản: từ đây mỗi lần gộp ghi thay đổi ở tệp này.

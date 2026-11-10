# Nhật ký thay đổi

Mỗi lần sửa (mỗi Pull Request): tăng VERSION (sửa lỗi → số cuối, tính năng → số giữa) và thêm đúng một mục mới ở đầu
danh sách, theo mẫu bên dưới. Hàng chờ gộp tự đổi sang số kế tiếp khi hai nhánh cùng lấy một số.

## 1.11.0 · 10/11/2026
### Tính năng
- Gửi video nhanh hơn, không phải ngồi chờ
  Video chọn từ mục Video được nén ngay trên điện thoại về chất lượng 720p trước khi gửi, nên nhẹ hơn nhiều lần
  (trên Android, video quay 1 phút còn khoảng 20 MB) và người nhận cũng mở xem nhanh hơn. Video nhỏ, hoặc máy không
  nén được, thì gửi bản gốc. Muốn gửi đúng bản gốc thì chọn video qua mục Tệp.
  Bấm Gửi được ngay khi video còn đang nén / tải: tin hiện liền trong khung chat với vòng tiến độ "Đang nén…" /
  "Đang tải lên", vẫn nhắn tiếp bình thường, thoát phòng chat thì video vẫn tải tiếp và tự gửi khi xong. Mất mạng
  giữa chừng thì tin báo lỗi, bấm thử lại sẽ tải tiếp phần còn thiếu.
  Tệp lớn được tải nhiều phần cùng lúc nên nhanh hơn trên mạng di động.

## 1.10.0 · 10/11/2026
### Tính năng
- Màn Phê duyệt trên app và duyệt nhanh từ thông báo
  Người có quyền thấy danh sách yêu cầu đang chờ và đã xử lý, xem chi tiết, bấm Duyệt hoặc Từ chối kèm ghi chú.
  Thông báo yêu cầu phê duyệt có sẵn nút Duyệt / Từ chối; bấm vào thông báo thì mở đúng yêu cầu đó. Mục này chỉ
  hiện khi máy chủ bật tính năng phê duyệt.
  Màn Nghiệp vụ có đường dẫn riêng để mở lại đúng chỗ từ thông báo. Workspace không có tab Nghiệp vụ thì ô Phê
  duyệt hiện ở tab Tất cả.
  Bấm Duyệt / Từ chối khi app đang chạy nền: lần mở app sau sẽ gửi lên máy chủ theo đúng workspace của yêu cầu và
  báo kết quả. Lần bấm của máy chủ khác hoặc đã quá 24 giờ thì không gửi mà báo rõ để xử lý lại.

## 1.9.1 · 10/11/2026
### Sửa lỗi
- App dựng được lại sau khi gộp đủ bốn lõi
  Lần gộp các lõi 1–4 làm trùng và thiếu mã ở phần thông báo, kết nối thời gian thực, hàng chờ gửi tin và thông
  tin máy chủ nên app không dựng được. Đã ghép lại để giữ đủ chức năng của cả bốn lõi.
- Giữ tuỳ chọn đăng nhập QR, duyệt thiết bị và xác minh email khi mở lại app
  Trước đây các tuỳ chọn này bị lưu sai chỗ nên mất khi app mở lại từ thông tin máy chủ đã lưu.
- Sửa số phiên bản trong nhật ký thay đổi
  Các mục của lõi 1, 3, 4 bị trùng số với mục cũ, nay đánh lại theo thứ tự.

## 1.9.0 · 10/11/2026
### Tính năng
- Hiển thị thẻ tin nhắn và thao tác ngay trong hội thoại
  Thêm biểu đồ, sơ đồ, kế hoạch, bảng, nút bấm và biểu mẫu theo khả năng máy chủ công bố.
- Theo dõi câu trả lời đang viết, xem lời chép và lịch sử tài liệu
  Ghép đoạn trả lời theo thứ tự; hỗ trợ lời chép tin thoại và xem, khôi phục ghi chú hoặc bảng trắng.

## 1.8.0 · 10/11/2026
### Tính năng
- Quyền riêng tư trong trò chuyện
  My Note có cache, quyền nhận cuộc gọi và khoá ứng dụng theo thời gian không dùng, giữ nguyên màn gọi.
  Hoàn thiện xác thực lại và cài đặt TOTP; gửi/xem tin bí mật qua API, không lưu nội dung vào draft hoặc outbox.
  Tin bí mật tự che sau 60 giây hoặc khi chạy nền; bật bảo vệ chụp màn hình Android trong lúc xem.
  Nhận sự kiện hết hạn để bỏ tin khỏi danh sách, giữ cờ/hạn dùng nhưng loại nội dung khỏi cache.

## 1.7.1 · 10/11/2026
### Sửa lỗi
- Nhận cuộc gọi trên một máy, gửi lại tin chờ ở mọi hội thoại
  Dừng chuông khi đã nhận trên máy khác và bỏ qua tín hiệu không dành cho máy này; giữ cuộc gọi của máy đang nghe.
  Gửi lại tin chờ khi mở app, có mạng hoặc kết nối lại, theo thứ tự trong từng hội thoại và giữ mã chống gửi trùng.
  Tải lại dữ liệu khi mốc đồng bộ hết hạn, khử sự kiện trùng; dừng hẹn gửi lại khi app vào nền. Cần máy chủ hỗ trợ
  các trường và sự kiện mới để dùng đầy đủ xử lý cuộc gọi nhiều thiết bị.

## 1.7.0 · 10/11/2026

### Tính năng
- Đăng nhập và quản lý thiết bị theo chính sách máy chủ
  Quét QR để đăng nhập máy tính, xác nhận hoặc từ chối thiết bị mới, xác minh email, nhận lời mời và chọn
  workspace. Hồ sơ hiển thị thêm chức danh, phòng ban, nơi làm và ngày vào công ty khi máy chủ hỗ trợ.
### Sửa lỗi
- Thu hồi máy khác không đăng xuất máy đang dùng
  Nhận diện phiên hiện tại bằng thông tin máy chủ; dọn dữ liệu phiên khi bị thu hồi, giữ luồng chờ duyệt và
  yêu cầu chọn rõ workspace khi tài khoản thuộc nhiều workspace.

## 1.6.0 · 10/11/2026
### Tính năng
- Theo dõi và xử lý phiếu hỗ trợ khách hàng
  Xem danh sách và chi tiết, phản hồi kèm ảnh, nhận thay đổi trực tiếp và chuyển trạng thái theo quyền được cấp.

## 1.5.0 · 10/11/2026
### Tính năng
- Bảng trắng dùng chung với web
  Vẽ nét, hình, chữ và biểu tượng; giữ các đối tượng từ web khi chỉnh sửa trên app. Hiện lỗi khi lưu thất bại để người dùng có thể thử lại.

## 1.4.0 · 10/11/2026
### Tính năng
- Quản lý việc trong phòng và xem Việc của tôi
  Tạo, giao, sửa, xoá và cập nhật trạng thái theo vai trò; lọc việc được giao, việc đã giao và quá hạn. Thông báo đưa thẳng đến việc liên quan.
- Cố định mốc giờ của bài kiểm thử quá hạn để kết quả không thay đổi theo ngày chạy.

## 1.3.1 · 10/11/2026
### Sửa lỗi
- Chuẩn hóa định dạng và cú pháp Dart để kiểm tra tự động không dừng trước bước test.

## 1.3.0 · 10/11/2026
### Tính năng
- Hiển thị tên và ảnh người gửi trong nhóm
  Tin nhắn nhóm hiển thị đúng người gửi, kể cả thành viên đã rời phòng; hội thoại trực tiếp giữ cách hiển thị hiện có.

## 1.2.0 · 02/11/2026
### Tính năng
- Xoá thông báo, mục Nghiệp vụ gọn theo nhóm, sửa tin nhắn thoại và tab Công việc
  Thông báo: vuốt sang trái hoặc giữ lâu để xoá từng cái, nút thùng rác trên cùng để xoá tất cả (có hỏi lại); cần máy
  chủ bản mới, máy chủ cũ sẽ báo chưa hỗ trợ. Mục Nghiệp vụ hiện dạng lưới ô chia nhóm Bán hàng / Hỗ trợ khách / Giám
  sát & cảnh báo / Kỹ thuật, thứ tự cố định Đơn hàng, Gia hạn, Kế toán, Doanh thu..., mỗi kênh có biểu tượng riêng;
  dải Nghiệp vụ ở Tất cả cũng theo thứ tự này. Tin nhắn thoại ghi trên web không còn hiện thành khung video. Tab Công
  việc: bấm Họp nhóm, Đã chia sẻ, Ghi chú chung, Bảng trắng, Việc cần làm không còn ra màn hình trống.

## 1.1.0 · 27/10/2026
### Tính năng
- Sửa gọi điện không có tiếng trên iPhone, thêm chuông, góp ý trong app và nhiều lỗi giao diện
  Cuộc gọi trên iPhone kết nối nhưng không nghe tiếng: app báo cho WebRTC khi CallKit bật âm thanh cuộc gọi. Gọi đi
  có chuông chờ đến lúc bên kia nhận máy; cuộc gọi đến khi đang mở app có nhạc chuông (kêu cả khi gạt im lặng) và rung.
  Danh bạ là mọi thành viên workspace, bấm là nhắn được ngay (không cần kết bạn), tìm bạn bè trong danh sách này. Thêm
  mục Cài đặt → Gửi góp ý. Sửa: hộp thoại Điều khoản hiện liên tục, tải ảnh đại diện không được, ô tìm kiếm không đóng
  được (chạm ra ngoài, kéo danh sách hoặc nút x để đóng). Bỏ chặn chụp / quay màn hình.
  Tin nhắn và nhóm / kênh gộp chung một hộp thư (bỏ tab Kênh): ghim lên đầu, còn lại theo tin mới nhất; lọc Tất cả /
  Chưa đọc / Cá nhân / Nhóm / Ghim (Bot khi dùng chat.vpsttt.com); kênh công khai chưa tham gia gợi ý ở cuối; nút soạn
  để nhắn riêng hoặc tạo nhóm.
  Sửa thêm trong phòng chat: tin vừa có chữ vừa có ảnh / tệp hiện đủ tệp; thả cảm xúc, ghim, sửa tin không làm mất
  ảnh / voice; quay lại app không hiện màn "đang tải" và không tự kéo xuống cuối khi đang đọc tin cũ; chưa cho gửi khi
  tệp còn đang tải lên (trước đây tệp đó bị bỏ). Danh sách hội thoại cập nhật khi rời phòng chat; mất mạng rồi có lại
  thì tự lấy bù tin bị lỡ; thông báo lỗi bằng tiếng Việt thay cho chữ kỹ thuật. Khung trả lời theo luồng tự hiện
  trả lời mới, sửa, thu hồi.
  Trên chat.vpsttt.com: dải "Nghiệp vụ" ở đầu hộp thư chứa các kênh bot (gia hạn, order, proxy, VPS...), bấm một lần
  là vào, kênh có tin chưa đọc đứng đầu rồi tới kênh dùng gần nhất; tab Nghiệp vụ đứng ngay sau Tất cả. Mỗi tab ghi số
  hội thoại chưa đọc. Mở kênh / tin riêng vào phòng ngay, không chờ tải lại danh sách.

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

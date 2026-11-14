# Nhật ký thay đổi

Mỗi lần sửa (mỗi Pull Request): tăng VERSION (sửa lỗi → số cuối, tính năng → số giữa) và thêm đúng một mục mới ở đầu
danh sách, theo mẫu bên dưới. Hàng chờ gộp tự đổi sang số kế tiếp khi hai nhánh cùng lấy một số.




## 1.18.3 · 14/11/2026
### Sửa lỗi
- Cài đặt: hiện logo tổ chức và bấm được mục Workspace
  Ô tròn ở thẻ đầu trang Cài đặt nay hiện logo của tổ chức (cùng logo ở góc trên bên trái) thay cho chữ viết tắt;
  máy chủ chưa đặt logo thì vẫn hiện chữ viết tắt như cũ. Mục "Workspace" trước đây có mũi tên nhưng bấm không có
  gì khi tài khoản chỉ thuộc một workspace; nay bấm vào mở danh sách workspace để xem workspace đang dùng, và khi vừa
  được mời vào workspace khác thì bấm "Tải lại" để thấy và chuyển sang. Cần cài bản app mới để thấy.

## 1.20.1 · 14/11/2026
### Sửa lỗi
- App kết nối realtime được với mọi máy chủ, gọi điện không còn kẹt "Đang kết nối"
  App nay gửi kèm địa chỉ máy chủ ("Origin") khi mở kết nối realtime. Các máy chủ chưa cập nhật từ chối kết nối thiếu
  thông tin này, làm app không nhận được tín hiệu cuộc gọi: bấm nghe xong vẫn đứng ở "Đang kết nối", không nghe được
  gì, và tin nhắn mới chỉ hiện khi app tự tải lại. Cần cài bản app mới để có thay đổi này.


## 1.20.0 · 14/11/2026
### Tính năng
- Màn Tin nhắn rộng chỗ hơn: bỏ thanh tiêu đề, dải Nghiệp vụ thu gọn
  Màn Tin nhắn không còn thanh tiêu đề "Tên tổ chức · Tin nhắn" ở trên cùng; chuông thông báo và nút soạn tin mới nằm
  ngay cạnh ô tìm kiếm. Dải kênh Nghiệp vụ (Đơn hàng, Gia hạn, Kế toán...) mặc định thu thành một dòng "Nghiệp vụ",
  kèm tổng số tin chưa đọc của các kênh; bấm vào dòng đó để mở ra / thu lại, app nhớ lựa chọn trong lúc đang dùng.
  Danh sách hội thoại vì thế hiện được nhiều hơn trên một màn hình. Các tab Bạn bè, Công việc, Cài đặt giữ nguyên.

## 1.19.1 · 14/11/2026
### Sửa lỗi
- Hộp "Điều khoản và quyền riêng tư" không còn bật lên mỗi lần mở app
  Trước đây mỗi lần mở app hoặc đổi workspace, hộp này che cả màn hình với dòng "Đang kiểm tra trạng thái chính
  sách..." dù người dùng đã đồng ý từ trước. Nay app kiểm tra ngầm: ai đã đồng ý thì không thấy gì nữa; hộp chỉ hiện
  khi máy chủ báo tài khoản thật sự chưa đồng ý (đồng ý một lần là xong, tới khi chính sách có phiên bản mới). Mất
  mạng lúc kiểm tra thì chỉ hiện một dải nhỏ phía trên có nút "Thử lại", không che màn hình. Gửi tin vẫn bị khoá cho
  tới khi kiểm tra xong như trước.

## 1.19.0 · 14/11/2026
### Tính năng
- Ảnh bìa cho video và ảnh thu nhỏ trong chat
  Gửi video thì app tự lấy một khung hình làm ảnh bìa gửi kèm, nên người nhận thấy ngay video là gì. Video trong
  khung chat hiện ảnh bìa, nút phát và thời lượng; chỉ khi bấm phát mới tải video (trước đây phải tải cả video mới
  thấy gì). Ảnh trong khung chat và kho "Ảnh, video, tệp" hiện bản nhỏ cho nhanh, bấm vào mở bản gốc. Cần máy chủ
  bản mới; máy chủ cũ thì hiện như trước.


## 1.18.2 · 14/11/2026
### Sửa lỗi
- Bấm kênh Ticket luôn mở màn trả lời ticket khách
  Trước đây bấm kênh Ticket trên điện thoại vẫn vào phòng chat với bot Ticket (nhất là khi kênh đã mở dạng phòng
  riêng, hoặc mở từ thông báo / máy tính bảng). Nay mọi lối vào kênh Ticket (danh sách hội thoại, ô kênh nghiệp vụ,
  thông báo, công cụ workspace, màn hình rộng) đều chuyển thẳng sang hộp thư Ticket khách, giống mục Ticket trên web,
  vì ticket đã về hết hộp thư này. Bỏ nút "Mở kênh chat Ticket". Người không có quyền xem ticket vẫn mở phòng chat
  như trước.

## 1.18.1 · 13/11/2026
### Sửa lỗi
- Bản build TestFlight không còn bị chặn bởi một test chập chờn
  Bước kiểm tra trước khi build đôi khi báo lỗi ở test "tải video theo từng phần, tối đa 3 phần cùng lúc" trên máy
  build chậm, dù app không có lỗi, làm bản build dừng giữa chừng. Nay test chờ đủ 3 phần cùng chạy rồi mới đo, nên
  kết quả ổn định. App không thay đổi gì.

## 1.18.0 · 12/11/2026
### Tính năng
- Bấm kênh Ticket là vào thẳng màn trả lời ticket khách
  Trước đây bấm kênh Ticket trong hộp thư chỉ mở khung chat của bot, còn màn trả lời ticket khách (giống mục Ticket
  trên web) nằm khuất ở tab Nghiệp vụ. Nay nhân viên có quyền xem ticket bấm kênh Ticket là mở ngay danh sách ticket
  (Chưa trả lời / Đã trả lời / Tất cả) để đọc và trả lời khách. Nút "Mở kênh chat Ticket" ở góc trên giúp quay lại
  khung chat của bot khi cần gõ lệnh. Người không có quyền xem ticket vẫn vào kênh chat như cũ.

## 1.17.3 · 12/11/2026
### Sửa lỗi
- Màn quét mã QR làm lại: camera tràn màn, khung quét lớn ở giữa
  Trước đây khi quét mã đăng nhập máy tính (hoặc quét QR trong chat), camera chỉ hiện một dải nhỏ ở đỉnh màn hình,
  khung quét bé và bị dòng chữ che, phần còn lại đen. Nay camera phủ cả màn hình, khung quét vuông lớn nằm giữa với
  4 góc trắng bo tròn và vạch quét chạy lên xuống (tự tắt khi điện thoại bật giảm chuyển động), chữ hướng dẫn nằm
  ngay dưới khung, nút Đèn pin to ở đáy và đổi màu khi đèn đang bật. Quét được mã thì điện thoại rung nhẹ. Không mở
  được camera (chưa cấp quyền, camera bận) thì hiện lời hướng dẫn rõ ràng kèm nút "Thử lại". Cần cài bản app mới để thấy.

## 1.17.2 · 12/11/2026
### Sửa lỗi
- App dùng đúng logo ở thanh bên trái của web
  Icon app trên Android và iPhone, logo màn đăng nhập, màn chờ khi mở app và icon trên Google Play nay cùng một logo
  với thanh bên trái của web: bóng chat xanh có chữ W trắng, đặt trên ô trắng. Trước đây Android 8 trở lên chỉ hiện
  một khối trắng có chữ W vì hình bị phóng quá khung. Icon đổi màu theo hình nền (Android 13+) cũng hiện đúng hình
  bóng chat có chữ W. Cần cài bản app mới để thấy.

## 1.17.1 · 12/11/2026
### Sửa lỗi
- Danh sách phiên đăng nhập gọn lại
  Màn Quyền riêng tư trước đây liệt kê mọi lần đăng nhập, kể cả các phiên đã thu hồi hay hết hạn từ lâu, nên rất dài.
  Nay chỉ hiện máy đang dùng và vài phiên còn hoạt động gần nhất (tối đa 3 phiên). Bấm "Xem tất cả" để xem hết, các
  phiên đã thu hồi / hết hạn xếp xuống cuối; bấm "Thu gọn" để ẩn lại.

## 1.17.0 · 11/11/2026
### Tính năng
- Bot AI đang vẽ biểu đồ thì ghi "Đang vẽ…" thay vì hiện dữ liệu thô
  Bot AI nay có thể trả biểu đồ, sơ đồ, kế hoạch hoặc bảng. Trong lúc bot còn đang trả lời, app giấu phần dữ liệu dùng
  để vẽ và ghi "Đang vẽ…" dưới tin. Trả lời xong thì tin hiện thẻ có hình như các thẻ bot khác.

## 1.16.0 · 11/11/2026
### Tính năng
- Lời tin nhắn thoại chạy theo tiếng
  Khi bấm "Xem lời" mà máy chủ có lời chia đoạn kèm giờ, app hiện từng đoạn kèm mốc giờ. Trong lúc nghe, đoạn đang nói
  được tô sáng và in đậm, khung lời tự cuộn tới đoạn đó mà không kéo cả khung chat. Chạm một đoạn thì tin thoại tua tới
  đầu đoạn và phát (chưa tải thì tải rồi phát). Máy chủ chỉ có lời gộp một khối thì vẫn hiện như cũ.


## 1.15.0 · 11/11/2026
### Sửa lỗi
- Phê duyệt hiện đúng tình trạng sau khi duyệt
  Trước đây phiếu đã duyệt có thể hiện "Đã thực hiện" dù chưa có gì được làm. Nay app hiện "Đã duyệt", "Đã duyệt –
  chờ bot thực hiện", "Đã duyệt – đang thực hiện", "Đã thực hiện" hoặc "Thực hiện lỗi" kèm lý do, theo thông tin
  máy chủ gửi. Máy chủ cũ chưa gửi thông tin mới thì app vẫn hiện như trước (không báo nhầm "Đã thực hiện").

## 1.14.0 · 11/11/2026
### Tính năng
- Gọi cả nhóm ổn định hơn và chuẩn bị phát hành đều đặn
  Mở app từ thông báo "gọi cả nhóm" (hoặc quay lại app) thì cuộc gọi còn đang đổ chuông hiện lại để bấm nhận. Đã từ
  chối thì thông báo tới muộn không làm máy đổ chuông lại; thời gian đổ chuông theo đúng giờ của máy chủ. Khi nhận gọi,
  app báo máy nào đã nhận để các máy khác của mình thôi đổ chuông. Đóng màn họp lúc đang kết nối thì app ngắt kết nối
  hẳn. Bản phát hành Android có thể tự đẩy lên kênh thử nội bộ của Google Play khi quản trị bật trong cài đặt CI; bài
  kiểm tra khởi động app chạy lại trong CI; tài liệu cũ đã được dọn cho bản mã nguồn mở.

## 1.13.0 · 11/11/2026
### Tính năng
- Họp LiveKit và gọi cả nhóm trên app
  Khi máy chủ bật họp LiveKit, app vào họp ngay trong app: xem lưới hình của mọi người, bật / tắt micro, camera, đổi
  camera trước / sau, chuyển loa, rời phòng; mất kết nối thì có nút thử lại, thiếu quyền micro / camera thì app giải
  thích cách cấp. Họp Jitsi vẫn mở bằng trình duyệt như cũ, và gửi kèm vé vào phòng khi máy chủ bật chế độ vé. Khi
  máy chủ bật gọi nhóm, người quản lý kênh có nút "Gọi cả nhóm" trong phòng cộng tác. Các thành viên khác nhận
  chuông "X đang gọi nhóm Y" như cuộc gọi thường: trên iPhone qua màn hình cuộc gọi của máy, trên Android qua thông
  báo cuộc gọi. Nhận thì vào thẳng phòng họp, từ chối thì máy khác của mình cũng thôi đổ chuông, người gọi huỷ thì
  chuông tắt. Máy chủ cũ chưa có các tính năng này thì app giữ nguyên như trước. Chưa thử trên iPhone và Android thật.

## 1.12.0 · 10/11/2026
### Tính năng
- Hộp thư khách trên app
  Khi máy chủ bật hộp thư khách, trang chủ có ô "Hộp thư khách": xem các cuộc trò chuyện của khách gửi qua email,
  Facebook, Zalo hoặc hệ thống khác, có nhãn nguồn, thẻ và người phụ trách; lọc theo trạng thái (đang mở / chờ
  khách / đã đóng) và theo người xử lý (của tôi / chưa gán). Trong một cuộc trò chuyện: đọc tin, trả lời khách (tin
  đi về đúng kênh khách đã nhắn), ghi chú nội bộ, nhận / bỏ nhận xử lý, đổi trạng thái, gắn thẻ. Tin gửi lỗi hiện
  trạng thái kèm lý do. Danh sách và tin mới tự cập nhật; bấm thông báo tin khách mới thì mở đúng cuộc trò chuyện.

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

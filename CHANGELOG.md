# Nhật ký thay đổi

Mỗi lần sửa (mỗi Pull Request): tăng VERSION (sửa lỗi → số cuối, tính năng → số giữa) và thêm đúng một mục mới ở đầu
danh sách, theo mẫu bên dưới. Hàng chờ gộp tự đổi sang số kế tiếp khi hai nhánh cùng lấy một số.

## 1.38.1 · 16/11/2026
### Sửa lỗi
- Trang đăng nhập / đăng ký ở giao diện tối không còn mất chữ
  - Trước đây nền, ô nhập, nút và các hộp cảnh báo cố định màu sáng, còn chữ tự đổi sang màu sáng khi bật nền tối nên
    chữ chìm vào nền. Nay mọi màu theo giao diện sáng / tối; thanh cảnh báo điều khoản cũng sửa theo.
  - Chữ phụ ở nền sáng đậm hơn một chút cho đủ độ tương phản 4,5:1.
- Mở bàn phím trong phòng chat không còn che tin nhắn cuối
  - Đang ở cuối cuộc trò chuyện thì khi bàn phím mở (hoặc đóng), danh sách tự đẩy lên để tin cuối nằm ngay trên ô soạn.
    Đang kéo lên đọc tin cũ thì danh sách giữ nguyên chỗ đang đọc.

## 1.36.0 · 16/11/2026
### Tính năng
- Thanh tab dưới thành viên thuốc nổi, kính trong kiểu Telegram
  - Thanh tab là khối bo tròn nổi cách hai mép màn hình và đáy (ngay trên thanh home / thanh cử chỉ). Danh sách cuộn ra
    phía sau và chạy hai bên; lớp kính làm mờ nội dung phía sau nên thấy màu ảnh, tin nhắn ánh qua mà chữ vẫn rõ. Có
    viền sáng mảnh ở mép trên và bóng đổ mềm.
  - Mục đang chọn có nền viên thuốc nhỏ trượt mượt sang tab mới, biểu tượng đặc + chữ xanh; mục khác là biểu tượng nét
    màu chữ chính. Bấm thì biểu tượng nhún nhẹ và máy rung nhẹ khi đổi tab. Máy bật giảm chuyển động thì không trượt.
  - Nền tối: kính tối sáng hơn nền một bậc, nền mục chọn tối hơn (như Telegram). Số chưa đọc vẫn là viên đỏ ở góc.
  - Chữ hệ thống rất lớn: nhãn tab giữ tối đa ×1,3 để không tràn khỏi viên thuốc. Máy tính bảng / màn rộng: viên thuốc
    rộng tối đa 520 điểm, nằm giữa. Vùng trong suốt quanh viên thuốc không chặn chạm vào nội dung phía sau.

## 1.35.2 · 16/11/2026
### Sửa lỗi
- Ảnh đại diện của bot (logo có góc trong suốt) không còn lộ nền xanh lá ở các góc. Từ giao diện mới, ảnh đại diện luôn
  vẽ một dải màu chọn theo tên nằm dưới ảnh, nên logo nào có phần trong suốt cũng bị lộ màu đó. Nay dải màu chỉ hiện
  khi chưa có ảnh (đi kèm chữ viết tắt hoặc biểu tượng nhóm / kênh); ảnh đã tải hiển thị đúng như ảnh gốc. Áp dụng mọi
  nơi có ảnh đại diện: danh sách Tin nhắn, đầu phòng chat, ảnh cạnh tin nhắn, danh bạ.

## 1.35.1 · 16/11/2026
### Sửa lỗi
- App không dựng được sau khi gộp giao diện liền mạch (1.35.0) với ảnh đại diện theo giới tính (1.33.0) và màn Việc của
  tôi (1.34.0): báo lỗi `gender` ở ảnh đại diện và `overdue` ở biểu tượng. Đã sửa, kèm trả lại phần bị mất khi gộp:
  - Người chưa có ảnh đại diện lại hiện hình người xám theo giới tính (kiểu Facebook) thay cho chữ viết tắt, kể cả ở
    đầu Cài đặt và danh sách Đồng nghiệp trong Bạn bè.
  - Hình người không còn viền màu mảnh ở mép tròn.
  - Nhãn "Quá hạn" trong Việc của tôi dùng biểu tượng đồng hồ báo thức cùng bộ biểu tượng mới.
- Sửa số phiên bản trong nhật ký: mục giao diện liền mạch là 1.35.0 (trước ghi nhầm 1.33.0, trùng số với mục ảnh đại
  diện theo giới tính).

## 1.35.0 · 16/11/2026
### Tính năng
- Giao diện mới liền mạch kiểu Zalo / Telegram: icon không khung, ảnh đại diện to và rõ mặt, thanh lọc trượt ngang kiểu
  YouTube
  - Icon: đổi sang bộ Phosphor (giấy phép MIT, đóng gói sẵn trong app). Bỏ mọi ô nền bao quanh icon; thanh tab dưới
    dùng icon nét màu xám khi chưa chọn, icon đặc màu xanh khi chọn; icon to hơn (tab 28px, nút đầu màn 26px).
  - Thanh tab dính sát đáy màn hình, nền kính mờ, thay cho viên thuốc nổi có nền bao mục đang chọn.
  - Ảnh đại diện: 56px ở danh sách hội thoại, 48px ở danh bạ, 92px ở đầu Cài đặt; ảnh canh lên phía mặt; chấm trạng
    thái nằm sát mép tròn, không đè vào mặt; người chưa có ảnh hiện 2 chữ cái trắng trên dải màu.
  - Thanh lọc ở Tin nhắn và Bạn bè: chip phẳng không viền, trượt ngang tràn mép, mờ dần ở mép phải khi còn chip; bấm
    chip thì rung nhẹ và tự cuộn chip đó vào giữa.
  - Bốn tab Tin nhắn, Bạn bè, Công việc, Cài đặt có tiêu đề lớn kiểu iOS; nội dung nằm thẳng trên nền trắng, các nhóm
    tách nhau bằng dải xám mảnh, đường kẻ giữa dòng thụt vào tới chữ (bỏ thẻ bo góc, viền, bóng).
  - Màu xanh nhấn đậm hơn một bậc và chữ xám phụ đậm hơn để chữ đạt tương phản tối thiểu 4,5:1.
  - Tin nhắn: tiêu đề lớn có nút soạn tin và chuông; ô tìm + thanh lọc (Tất cả, Nhóm, Cá nhân, Chưa đọc kèm số) dính
    trên cùng khi cuộn. Dòng hội thoại: tên, giờ, ghim ở hàng trên; tin cuối và số chưa đọc ở hàng dưới; nhóm tắt
    thông báo có chuông gạch cạnh tên và số chưa đọc màu xám.
  - Bạn bè: hai chip Đồng nghiệp / Nhóm kèm số; dòng đồng nghiệp chỉ còn ảnh, tên, email. Bỏ nút khiên cuối dòng, báo
    cáo / chặn vẫn mở bằng nhấn giữ (trình đọc màn hình có hành động riêng).
  - Công việc: Việc của tôi (3 cột số + việc gần hạn), lưới Ứng dụng dùng icon hai tông màu không ô nền, thêm nhóm
    Họp sắp tới (3 cuộc họp gần nhất chưa huỷ, bấm mở chi tiết). Bỏ dòng "Chưa có lối tắt".
  - Cài đặt: đầu màn có ảnh đại diện lớn, tên, email và nút Sửa hồ sơ; dòng cài đặt chữ thường, giá trị xám bên phải,
    công tắc kiểu iOS. Đổi tên "Danh sách dày" thành "Danh sách gọn".

## 1.34.0 · 16/11/2026
### Tính năng
- Màn Việc của tôi thiết kế lại rõ ràng, hiện đại
  Ba ô đếm Chưa nhận / Đã nhận / Hoàn thành (7 ngày qua) làm bộ lọc, cùng màu với thẻ Việc của tôi ở tab Công việc. Việc
  chưa xong chia nhóm theo hạn: Quá hạn (tô đỏ), Hôm nay, Ngày mai, 7 ngày tới, Sau này, Không có hạn; mỗi việc là một
  thẻ trong khối bo tròn có ô trạng thái (bấm để nhận / hoàn thành, có Hoàn tác), tên việc tối đa 2 dòng, nhãn hạn màu
  ("Quá hạn 2 ngày", "Hôm nay 17:00", "Hạn 20/11") và tên nhóm. Việc đã xong chia Hôm nay / Hôm qua / Trước đó với nhãn
  "Xong 09:05". Tìm theo tên chia kết quả theo trạng thái. Khi trống có lời hướng dẫn theo từng mục; hỗ trợ nền tối và
  tiếng Anh.

## 1.33.0 · 16/11/2026
### Tính năng
- Ảnh đại diện mặc định theo giới tính (kiểu Facebook): người chưa đặt ảnh đại diện (hoặc ảnh không tải được) hiện
  hình người màu xám thay cho nền màu + chữ viết tắt. Nam → hình nam, nữ → hình nữ, chưa chọn hoặc "Không muốn nói" →
  hình người trung tính. Có cả bản nền tối. Áp dụng ở danh sách tin nhắn 1-1, đầu phòng chat, ảnh cạnh tin nhắn (cả
  trong nhóm), danh bạ, thành viên nhóm, chọn thành viên khi tạo nhóm, hồ sơ cá nhân, người được giao việc. Ảnh nhóm,
  kênh, bot, chat bot thông báo và tin do bot gửi giữ như cũ.
- Hồ sơ cá nhân có thêm mục "Giới tính" (Nam / Nữ / Không muốn nói): chọn là lưu ngay, ảnh đại diện mặc định đổi theo;
  lưu lỗi thì báo và giữ lựa chọn cũ. Cần máy chủ đã cập nhật bản có giới tính; máy chủ cũ thì mọi người hiện hình
  trung tính.


## 1.32.1 · 16/11/2026
### Sửa lỗi
- Tin chưa đọc dễ nhận ra hơn: trong danh sách Tin nhắn, dòng xem trước của hội thoại còn tin chưa đọc in đậm, màu chữ
  đậm; giờ gửi tô xanh. Đọc xong thì trở về chữ xám thường. Áp dụng cả dòng bot thông báo.
- Bảng Công việc của nhóm: chip đang chọn (Tổng quan, Họp, Đã chia sẻ, Biên bản...) không còn vòng tròn xám đè lên
  biểu tượng (trông như lỗi hover); chip đang chọn chỉ đổi nền xanh.
- Đổi cách gọi "kênh" thành "nhóm" trên giao diện app (Xoá nhóm, Chi tiết nhóm, tab Nhóm trong Bạn bè, Nhóm đã tham
  gia / có thể tham gia, thông báo lỗi, cài đặt thông báo...), cả bản tiếng Anh (channel → group). Thanh dưới chat bot
  thông báo ghi "Bot thông báo, không trả lời được". Giữ chữ "kênh" ở phần nghiệp vụ (kênh bán hàng của hộp thư khách,
  bot tạo phiên riêng).

## 1.32.0 · 16/11/2026
### Tính năng
- Lịch họp đầy đủ: tạo họp, xem theo tuần, sửa / dời / huỷ, nhắc họp, mời và phản hồi, họp định kỳ, biên bản, kiểm
  trùng lịch, link cho khách
  - Màn Lịch họp (ô "Lịch họp" trong tab Công việc): dải 7 ngày có chấm ở ngày có họp, chuyển tuần trước / tuần sau,
    tab Sắp tới / Đã qua; mỗi thẻ có nhãn trạng thái và phản hồi của mình. Nút + ở đầu màn để tạo họp.
  - Tạo họp: chọn nhóm có sẵn, hoặc chọn từng người thì app tạo một nhóm riêng tư mới cho cuộc họp. Đặt ngày giờ, nội
    dung, link họp ngoài (chỉ https) nếu không dùng phòng video sẵn có, mốc nhắc, người tham dự (cả nhóm hoặc chọn
    người). Khi chọn giờ, app báo người nào đã có họp khác trùng giờ.
  - Nhắc họp: mặc định 15 phút trước và lúc bắt đầu, đổi được (0 / 5 / 10 / 15 / 30 / 60 phút, tối đa 3 mốc). Bấm
    thông báo nhắc họp hoặc thông báo họp bị đổi là mở thẳng chi tiết cuộc họp.
  - Họp định kỳ: hằng ngày / hằng tuần (chọn thứ) / hằng tháng, kết thúc theo ngày hoặc số buổi (tối đa 100 buổi, trong
    1 năm). Sửa hoặc huỷ một buổi lặp lại thì hỏi "Chỉ buổi này" hay "Cả chuỗi"; sửa cả chuỗi thì buổi đã sửa riêng
    trước đó giữ nguyên.
  - Chi tiết cuộc họp: "Vào họp" mở từ 10 phút trước giờ họp (link ngoài thì mở link, không thì vào phòng video), "Nhắn
    vào nhóm", phản hồi Tham gia / Có thể / Từ chối, danh sách người dự.
  - Biên bản họp: soạn, lưu, gửi vào nhóm; giao việc cho người dự ngay từ cuộc họp.
  - Link cho khách: người tổ chức bật / tắt link để người ngoài xin vào họp (người tổ chức duyệt); có nút sao chép.
    Nhóm đang bật một link công khai khác thì app báo cần tắt link đó trước.
  - Cần máy chủ bản có Lịch họp mới; máy chủ cũ thì màn Lịch họp vẫn liệt kê họp sắp tới như trước.

## 1.31.2 · 16/11/2026
### Sửa lỗi
- Nút "+ Ghi chú mới" gọn lại, thẻ cuộc gọi nhỡ của bot ghi rõ ai gọi, danh sách chat hiện số tin chưa đọc
  - Nút nổi "Ghi chú mới" trước là hình tròn xanh, chữ tràn ra ngoài; nay là nút dạng viên thuốc, chữ nằm gọn bên trong.
    Áp dụng chung cho mọi nút nổi có chữ trong app.
  - Tin "cuộc gọi nhỡ" của bot thông báo nay hiện đúng thẻ của bot: ghi "<tên> đã gọi cho bạn", có nút "Gọi lại" (gọi
    thẳng người đó) và "Mở cuộc trò chuyện". Trước đây app coi nó như tin cuộc gọi nhỡ trong phòng bot, không ghi tên
    người gọi, bấm "Gọi lại" bị báo "Cuộc gọi chỉ thực hiện trong tin nhắn 1-1".
  - Danh sách Tin nhắn hiện huy hiệu đỏ số tin chưa đọc bên cạnh từng chat: chat 1-1 hiện 1–5, quá 5 ghi "5+"; nhóm hiện
    1–99, quá 99 ghi "99+".
  - Có tin mới thì số này tự tăng ngay và hội thoại lên đầu danh sách, không phải kéo để tải lại. App cộng tại chỗ từ
    tin vừa đến, không gọi lại máy chủ; tin của chính mình và hội thoại đang mở (máy tính bảng) không được cộng.
  - Cần máy chủ bản 1.44.1 trở lên mới có số chưa đọc của nhóm; máy chủ cũ chỉ có ở chat 1-1.

## 1.31.1 · 16/11/2026
### Sửa lỗi
- Bản Android dựng được trở lại, thư viện giải mã ghi âm đạt căn lề 16 KB
  - Từ bản 1.30.0, CI không dựng được app Android, báo lỗi CXX1110. Nguyên nhân là thư viện giải mã ghi âm WebM / Ogg
    (opus_flutter_android) khai Android tối thiểu API 19, mà bộ dịch NDK của Flutter chỉ nhận từ API 21. App vốn chỉ
    cài được từ API 24 nên nay cho phần này dịch ở mức 21.
  - Thư viện đó cũng được dịch bằng NDK cũ nên libopus chỉ căn lề 4 KB, không qua bước kiểm 16 KB của bản phát hành
    (Google Play đòi cho Android 15+). Nay nó được dịch bằng cùng NDK với app và đạt 16 KB.

## 1.31.0 · 16/11/2026
### Tính năng
- Rời nhóm và xoá nhóm
  - Trong phòng chat nhóm, menu ≡ và màn thông tin nhóm có thêm "Rời nhóm" và "Xoá nhóm"; cả hai đều có hộp xác nhận.
  - Rời nhóm: nhóm biến mất khỏi Tin nhắn của mình, người khác vẫn nhắn tiếp. Người cuối cùng rời thì nhóm tự xoá.
  - Xoá nhóm: chỉ người tạo nhóm hoặc quản trị làm được; nhóm biến mất ở mọi thành viên và không mở lại được.
  - Đang mở một nhóm mà nhóm đó bị người khác xoá thì app tự đóng và báo "Nhóm đã bị xoá".
  - Không có ở chat 1-1 và kênh bot.
  - Cần máy chủ bản có Rời / Xoá nhóm; máy chủ cũ thì không hiện hai nút này.

## 1.30.0 · 16/11/2026
### Tính năng
- Cài đặt gọn lại, cả app có tiếng Anh, chọn được giao diện Sáng / Tối; video trong Tệp có ảnh xem trước; iPhone nghe được
  mọi ghi âm; thanh tab không còn vệt xám ở tab cũ; tạo nhóm hiện đủ thành viên
  Đầu tab Cài đặt nay là một thẻ có ảnh đại diện, tên và dòng "Hồ sơ cá nhân"; bấm vào mở màn Hồ sơ, trong đó có mục
  "Tài khoản và bảo mật". Bỏ hai dòng "Hồ sơ cá nhân" và "Tài khoản" bị trùng ở dưới. Chọn "English" trong Thiết lập
  ứng dụng thì cả app đổi sang tiếng Anh ngay (Tin nhắn, phòng chat, gọi điện, Công việc, Nghiệp vụ, Ticket khách,
  Ghi chú, Phê duyệt, Cài đặt, thông báo lỗi...), không phải mở lại app. Vẫn còn tiếng Việt: nội dung tin nhắn, tên
  kênh và thông báo do máy chủ gửi về, màn chọn máy chủ trước khi đăng nhập. Ghi âm dạng WebM / Ogg (thường gửi từ web) trước đây iPhone không phát được; nay app tự đổi
  sang dạng iPhone đọc được ngay trên máy (lần đầu chờ một chút, lần sau phát ngay; bản đã đổi bị xoá cùng tệp tải về khi đăng xuất), nên ở mục Tệp và trong phòng chat
  đều nghe được mọi ghi âm. Nếu một tệp vẫn không đổi được thì app mở bảng "Mở bằng ứng dụng khác".
  Thanh tab nổi (có từ 1.29.0): bấm sang tab khác thì chỉ tab đó đổi màu, tab cũ không còn vệt xám đọng lại; chữ tab
  đang chọn xanh đậm hơn cho dễ đọc, bóng dưới thanh nhẹ hơn; tên tab đổi theo ngôn ngữ đang chọn.
  Tạo nhóm: nhóm mới mở ra hiện đúng số thành viên vừa chọn (trước đây hiện chỉ có mình người tạo) và nhóm riêng tư
  vừa tạo hoặc vừa được thêm vào hiện ngay trong mục Tin nhắn, không phải chờ có tin đầu tiên. Thêm người nào lỗi thì
  app báo "Không thêm được N người". Đang mở app mà bị người khác thêm vào nhóm thì nhóm hiện ngay trong Tin nhắn
  (cần máy chủ đã cập nhật bản hỗ trợ), không phải kéo tải lại.
  Thiết lập ứng dụng → Giao diện: chọn "Tối" thì cả app đổi sang nền tối ngay (không phải mở lại app, không mất màn
  đang mở); "Hệ thống" thì theo chế độ sáng / tối của điện thoại. Màn đăng nhập vẫn giữ nền sáng. Tệp chia sẻ → Video:
  video cũ chưa có ảnh xem trước nay được app tự lấy một khung hình làm ảnh bìa (lấy ngay trên máy, lưu lại cho lần
  sau), không còn ô đen. Trên iPhone, video dạng WebM không lấy được ảnh nên vẫn hiện biểu tượng video.
  Số tin chưa đọc (danh sách tin, thanh tab dưới, lối tắt Ticket khách) luôn là viên tròn gọn 18px, giãn ngang theo
  số ("99+"), không còn bị kéo dài thành hình bầu dục.

## 1.29.1 · 15/11/2026
### Sửa lỗi
- Chạy thử app trên Dev VPS bằng `vpsttt-app run` không còn báo lỗi
  Trước đây lệnh báo "No Linux desktop project configured" vì app chưa có phần dựng cho Linux (công cụ chạy thử mở bản
  Linux của app trong khung điện thoại). Thêm phần đó xong thì máy dev lại thiếu thư viện cho hai gói: âm thanh và kho
  lưu phiên đăng nhập. Nay app có thư mục Linux, và riêng bản chạy thử dùng hai gói thay thế: không phát âm thanh, phiên
  đăng nhập chỉ giữ tới khi tắt app. Bản Android / iOS phát hành không đổi gì. Cách chạy thử ghi ở README, mục "Chạy
  Thử Trên Dev VPS".

## 1.29.0 · 15/11/2026
### Tính năng
- Thanh điều hướng dưới dạng nổi như Telegram; ô nhập tin sát đáy; ô Ứng dụng đều nhau
  - Thanh Tin nhắn / Bạn bè / Công việc / Cài đặt giờ là thanh nổi hình viên thuốc, nền kính mờ, cách hai mép màn
    hình. Mục đang chọn có nền viên thuốc phía sau. Danh sách cuộn ra phía sau thanh, cuộn hết thì mục cuối vẫn nằm
    trên thanh.
  - Phòng chat: bỏ dải trống thừa dưới ô nhập tin. Nền trắng của ô nhập chạy tới mép màn hình, hàng nhập nằm sát ngay
    trên thanh home của iPhone (Android giữ đúng chỗ thanh điều hướng). Khi bàn phím mở, ô nhập sát bàn phím.
  - Khu Ứng dụng ở tab Công việc: ô biểu tượng Lịch họp, Tệp chia sẻ, Thêm cùng kích thước và cùng bo góc; chữ bên
    dưới thẳng hàng.

## 1.27.2 · 15/11/2026
### Sửa lỗi
- App mời bật thông báo để nhận cuộc gọi khi đang tắt app
  Trước đây app chỉ xin quyền thông báo khi người dùng tự vào Cài đặt bấm "Cho phép". Ai chưa bấm thì máy chủ không
  đánh thức được app đang tắt, nên có người gọi mà điện thoại không đổ chuông, phải mở app mới thấy. Nay sau khi đăng
  nhập (đã qua hộp Điều khoản), app hiện hộp "Nhận cuộc gọi khi tắt app". Bấm "Cho phép" thì điện thoại hỏi quyền
  thông báo; được cho phép thì app đăng ký với máy chủ để nhận cuộc gọi và tin nhắn khi đang tắt. Bấm "Để sau" thì 7
  ngày sau mới nhắc lại. Từ chối ở hộp của điện thoại thì app không nhắc nữa, người dùng tự bật trong cài đặt điện
  thoại. iPhone còn cần máy chủ cài khoá Apple (APNs) mới đổ chuông được khi tắt app.

## 1.28.0 · 15/11/2026
### Tính năng
- Ảnh đại diện nhóm; người gọi không còn thấy hộp "Cuộc gọi đến" của chính cuộc mình gọi
  Nhóm có ảnh đại diện: mở thông tin nhóm, bấm "Đổi ảnh nhóm" (hoặc bấm vào ảnh nhóm), chụp mới hay chọn ảnh có sẵn rồi
  cắt vuông; ảnh hiện ở danh sách Tin nhắn, đầu phòng chat, tab Kênh và thông tin nhóm. Thành viên nào của nhóm cũng đổi
  được; kênh công khai chỉ người quản lý kênh đổi được. Cần máy chủ 1.38.0 trở lên. Sửa lỗi bấm gọi (thoại hay video)
  thì máy người gọi cũng hiện hộp "Cuộc gọi đến — Nghe / Từ chối": app nay nhớ các cuộc do chính máy mình gọi (kể cả
  khi máy chủ báo trước khi tạo xong cuộc gọi), nhận ra cuộc gọi đi từ máy khác cùng tài khoản theo tài khoản đã đăng
  nhập trên máy (không cần tải hồ sơ qua mạng như trước), và tự đóng hộp nếu lỡ hiện. Người được gọi vẫn đổ chuông như cũ.


## 1.27.1 · 15/11/2026
### Sửa lỗi
- Đầu phòng chat gọn lại, tên người hiện đủ
  Đầu phòng chat chỉ còn hai nút gọi thoại, gọi video và nút ba gạch (≡). Tìm tin nhắn, báo cáo hoặc chặn, công cụ
  làm việc và chi tiết kênh nằm trong menu của nút ba gạch. Các nút, ảnh đại diện nhỏ gọn hơn; chữ tên tự nhỏ dần khi
  thiếu chỗ. Nhờ vậy tên ba chữ như "Nguyễn Thanh Tiền" hiện đủ trên điện thoại khổ hẹp (360–390 điểm). Tên nhóm quá
  dài vẫn bị cắt bằng "…".

## 1.27.0 · 15/11/2026
### Tính năng
- Kênh vào Danh bạ, Tin nhắn hiện sẵn các kênh đang dùng
  Màn Bạn bè có hai tab "Đồng nghiệp" và "Kênh". Tab Kênh liệt kê kênh bạn đã tham gia (kể cả kênh chưa có tin) và
  kênh công khai có thể tham gia, có ô tìm theo tên; bấm kênh đã tham gia là vào chat ngay. Danh sách Tin nhắn gộp
  chat riêng với kênh, xếp theo tin mới nhất: luôn có ba kênh Chung, Thông báo, Trò chuyện, cùng mọi kênh bạn tham
  gia đã có tin nhắn; kênh chưa có tin chỉ nằm ở Bạn bè > Kênh. Khu "Nhóm có thể tham gia" cuối Tin nhắn chuyển
  sang tab Kênh. Máy chủ chưa cập nhật thì kênh khác chỉ hiện ở Tin nhắn khi còn tin chưa đọc.

## 1.26.1 · 15/11/2026
### Sửa lỗi
- Chat 1-1 chỉ hiện avatar người kia cạnh tin, không lặp tên người gửi
  Trong cuộc trò chuyện riêng, tin của người kia giờ có avatar nhỏ bên trái (giống Zalo) thay vì dòng tên lặp lại trên
  mỗi cụm tin, kể cả thẻ cuộc gọi đến. Nhóm và kênh vẫn hiện tên người gửi như cũ để biết ai nói.

## 1.26.0 · 14/11/2026
### Tính năng
- Gọi điện không còn kẹt "Đang kết nối", video có ảnh xem trước, hiện tên người gửi, biểu tượng kênh có màu
  Cuộc gọi đi từ một thiết bị không còn đổ chuông nhầm trên thiết bị khác đăng nhập cùng tài khoản (trước đây bấm
  nhận ở đó sẽ kẹt "Đang kết nối"). Bắt máy không được (cuộc gọi đã kết thúc hoặc đã nhận ở máy khác) thì app báo rõ rồi
  tự đóng; sau 40 giây vẫn chưa nối được tiếng thì báo "Không kết nối được, vui lòng thử lại" và kết thúc gọn.
  Video cũ chưa có ảnh bìa tự lấy khung hình đầu để xem trước; bấm phát là xem ngay trong lúc tải dần, không phải chờ
  tải hết. Tin của người khác hiện tên người gửi ở tin đầu mỗi cụm, cả trong nhắn riêng lẫn nhóm. Biểu tượng kênh
  mỗi loại một màu (Chung xanh dương, Thông báo cam, Trò chuyện xanh ngọc, bot tím...).

## 1.25.0 · 14/11/2026
### Tính năng
- Tệp chia sẻ thiết kế lại gọn và hiện đại
  Tệp chia theo nhóm thời gian (Hôm nay, Hôm qua, Tháng này, từng tháng cũ hơn) trong các khối bo tròn; nút lọc dạng
  viên kèm số tệp từng loại; có ô tìm tệp theo tên. Lọc Ảnh / Video hiện dạng lưới ảnh thu nhỏ (chia theo tháng), video
  có thời lượng. Tên do máy tự đặt (voice-…, image_picker_…, chuỗi ký tự dài) hiện gọn thành "Ghi âm", "Video", "Ảnh";
  dòng phụ chỉ còn đuôi tài liệu, thời lượng, kích thước và giờ / ngày. Ghi âm có nút nghe tròn; video chưa có ảnh bìa
  (gửi từ bản cũ) hiện ô tối có dấu phát thay vì ô lỗi. Chữ phụ đậm hơn cho dễ đọc.

## 1.24.0 · 14/11/2026
### Tính năng
- App gọn hơn, xem tệp ngay, hộp thoại làm mới theo góp ý đợt 2
  Tin nhắn: tab Nghiệp vụ chỉ còn 3 kênh Đơn hàng, Gia hạn, Kế toán; các kênh hệ thống khác (giám sát, cảnh báo,
  webhook, nhật ký...) ẩn khỏi app (máy chủ và web giữ nguyên). Nút lọc theo thứ tự Tất cả, Nhóm, Cá nhân (chat 1-1),
  Nghiệp vụ, Chưa đọc; chat bot thông báo không tính vào Nhóm hay Cá nhân. "Tạo kênh" đổi thành "Tạo nhóm": đặt tên,
  mô tả, chọn thành viên ngay khi tạo, nhóm luôn riêng tư (thêm người lỗi thì nhóm vẫn tạo và báo số người chưa thêm).
  Chat: ảnh và video hiện đúng tỉ lệ, sát phía người gửi, giờ nằm ở góc ảnh; thẻ cuộc gọi chỉ còn một biểu tượng
  hướng gọi (đến / đi / nhỡ) và nút "Gọi lại"; "Tạo bình chọn" chỉ có trong nhóm, không có ở chat 1-1.
  Công việc: bỏ tiêu đề lớn, nút tìm nhỏ cạnh "Xem tất cả"; biểu tượng tab Công việc là chiếc cặp.
  Tệp chia sẻ: ảnh và video có ảnh thu nhỏ, tài liệu có logo PDF / Word / Excel / PowerPoint; bấm ghi âm là nghe ngay
  tại dòng; video phát ngay không cần tải hết tệp; PDF xem ngay trong app; tệp đã mở được lưu tạm (xoá khi đăng
  xuất) để lần sau mở tức thì; lưu / chia sẻ tệp qua "Mở bằng ứng dụng khác".
  Mọi hộp thoại và bảng chọn đổi sang kiểu mới đồng bộ (nền trắng, bo tròn, nút lớn, thao tác xoá / chặn nút đỏ);
  My Note gom việc chọn, tạo, đổi tên, xoá thư mục vào một bảng Lọc; hộp "Xác thực lại" chọn cách xác thực bằng nút.

## 1.23.0 · 14/11/2026
### Tính năng
- Màn chat mới theo ảnh mẫu, có "Đã xem"
  Đầu trang có ảnh, tên và trạng thái hoạt động thật ("Đang hoạt động" hoặc "Hoạt động N phút trước"), nút gọi thoại,
  gọi video và nút "…" gom các công cụ khác. Tin của mình màu xanh, của người khác màu trắng; ảnh và video hiện sát viền,
  giờ nằm ngay trên ảnh, chú thích tách thành bong bóng riêng; tin thoại có nút phát và sóng âm; thẻ cuộc gọi có nút gọi
  lại (cuộc gọi nhỡ chữ đỏ). Ô nhập có nút "+", biểu tượng cảm xúc trong ô, nút mic đổi thành nút gửi khi đã gõ chữ. Chat
  1-1 hiện "Đã xem" dưới tin cuối của mình khi người kia đã đọc (cần máy chủ bản mới).

## 1.22.0 · 14/11/2026
### Tính năng
- Màn Tin nhắn và tab Công việc mới theo ảnh mẫu
  Màn Tin nhắn gọn hơn: bỏ tiêu đề lớn, nút soạn tin nằm bên trái ô tìm, các nút lọc Tất cả / Chưa đọc / Nghiệp vụ / Nhóm,
  kênh có biểu tượng riêng trong ô vuông, người có ảnh tròn và chấm xanh khi đang hoạt động. Thanh dưới nổi bo tròn 4 mục
  với bộ biểu tượng mới (cùng họ với bản web). Tab Công việc có "Việc của tôi" (số việc Chưa nhận / Đã nhận / Hoàn thành,
  các việc sắp tới hạn, bấm ô vuông để nhận hoặc hoàn thành việc), My Note, và khối "Ứng dụng" gồm Lịch họp chung, Tệp
  chia sẻ và các lối tắt do quản trị thêm (quản trị thấy ô "Thêm" và "Quản lý"). Máy chủ chưa cập nhật thì ẩn Lịch họp và
  lối tắt.
  Số đỏ trên tab Tin nhắn đếm mọi tin chưa đọc (không đổi theo nút lọc hay ô tìm đang chọn), không tính chat đã tắt
  tiếng và người đã chặn. Nút lọc không thu nhỏ chữ: máy màn hẹp thì vuốt ngang để xem hết. "Hoàn thành" ở màn Việc
  của tôi chỉ liệt kê việc xong trong 7 ngày qua cho khớp ô đếm; việc cũ hơn tìm theo tên.
  Thay đổi khác cần biết: bỏ hai nút lọc "Cá nhân" và "Ghim" (chat ghim vẫn nằm đầu danh sách); bỏ dải kênh nghiệp vụ
  trên đầu danh sách (xem ở nút lọc "Nghiệp vụ"); tab Công việc bỏ thẻ "chọn phòng + công cụ cộng tác" (công cụ cộng tác
  vẫn mở được trong phòng chat). My Note làm lại: soạn có định dạng (đậm, nghiêng, tiêu đề, danh sách, ô tick, mã), liên
  kết bấm được; bảng Lọc theo thư mục / thẻ / ghim, quản lý thư mục chuyển vào bảng Lọc.

## 1.21.0 · 14/11/2026
### Tính năng
- Thông báo chuyển sang chat với bot, bỏ nút chuông
  Trên máy chủ đã cập nhật, app không còn nút chuông và danh sách thông báo. Các thông báo (cuộc gọi nhỡ, được giao
  việc, nhắc hẹn, lời mời kết bạn, duyệt yêu cầu, hộp thư khách, đăng nhập thiết bị mới) đến dưới dạng tin của
  "<Tên tổ chức> Bot" trong một cuộc chat riêng, như bot trên Telegram. Mỗi tin là một thẻ có nút: "Mở việc", "Mở
  hội thoại", "Gọi lại", "Chấp nhận / Từ chối" lời mời... bấm là tới đúng màn hoặc xử lý ngay. Lỗi khi bấm nút hiện
  ngay dưới hàng nút. Chat bot chỉ đọc (không gõ được) và có mục "Tắt / Bật thông báo" trong menu ba chấm. Liên kết
  cũ mở màn thông báo nay mở chat bot. Máy chủ chưa cập nhật thì app vẫn giữ nút chuông như cũ.


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

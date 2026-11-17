# Reference UI Mobile WebTui

## File ảnh bắt buộc

```text
docs/design/mobile/references/webtui-mobile-zalo-reference.png
```

Khi triển khai Flutter UI, phải mở ảnh này trước khi viết layout. Nếu file ảnh chưa tồn tại, dừng phần dựng UI và yêu cầu đặt ảnh gốc vào đúng path.

## Hướng thiết kế đã chốt

Mobile app WebTui phải đi theo mẫu Zalo-like chuyên nghiệp, sáng, gọn, nhiều thông tin nhưng không rối.

Các màn hình chính trong reference:

| Màn | Ý nghĩa thiết kế | Điểm cần bám |
|---|---|---|
| Splash/Login | Nhận diện WebTui, đăng nhập nhanh | Logo nổi ở giữa, nền sáng, nút đăng nhập gọn |
| Tin nhắn | Màn mặc định sau đăng nhập | Không có tiêu đề: hàng [nút soạn (bút)][ô tìm] ngay dưới thanh trạng thái, hàng chip lọc kiểu Messenger, danh sách hội thoại |
| Bạn bè | Danh bạ và kênh/bot tích hợp | Tab "Hội thoại" và "Kênh & Bot", list item dày, trạng thái chưa đọc |
| Kênh | Danh sách channel theo workspace | Search/settings, channel category, badge trạng thái tham gia/mở kênh |
| Công việc | Việc của tôi, ứng dụng, họp sắp tới | Không có tiêu đề: ô tìm giả (chỉ bấm, mở tìm việc) ở đầu nội dung |
| Cài đặt | Profile và thiết lập WebTui nâng cao | Không có tiêu đề: thẻ hồ sơ (avatar lớn, tên) bắt đầu ngay dưới thanh trạng thái, card setting, toggle, slider |

## Design tokens định hướng

| Nhóm | Guideline |
|---|---|
| Nền | Sáng, xám rất nhạt, không dùng gradient nặng |
| Primary | Xanh WebTui/Zalo-like cho active tab, badge, action chính |
| Border | Mảnh, độ tương phản thấp, dùng để tách list/card |
| Radius | Vừa phải; card/list item khoảng 10-16px, không bo quá tròn kiểu landing page |
| Shadow | Rất nhẹ, chỉ dùng cho phone mock/card nổi cần phân cấp |
| Typography | Rõ, gọn, ưu tiên scan nhanh; tên người/kênh đậm vừa |
| List density | Dày hơn landing page, mỗi item đủ avatar, tên, preview, thời gian/badge |
| Bottom navigation | 4 tab chính: Tin nhắn, Danh bạ, Khám phá/Kênh, Thêm/Cài đặt |
| Thanh tab dưới | Viên thuốc nổi kính trong cao 56 (viên chọn cao 48), biểu tượng 24, chữ 10.5; mỗi mục bấm ≥ 44; danh sách chừa đáy theo `WebTuiFloatingTabBar.contentBottomPadding` |
| Segmented tabs | Dùng cho Hội thoại/Kênh & Bot, Tất cả/Chưa đọc/Yêu thích |
| Chip lọc (`WebTuiFilterChipBar`) | Kiểu Messenger: viên thuốc cao 32, không viền, nền xám nhạt (`chipBackground`), chữ đậm 600 màu phụ; chip chọn nền primary trong suốt 14% (tối 20%), chữ primary đậm; số đếm nhỏ nằm trong chip |
| Icon | Dùng icon mềm, quen thuộc, không dùng icon cứng/AI-looking |
| Nút nổi (FAB) | Theme dùng `StadiumBorder`: nút chỉ icon vẫn tròn 56×56; nút có chữ (`FloatingActionButton.extended`, vd "Ghi chú mới") là viên thuốc, lề trái 16 / phải 20, icon cách chữ 8, chữ `labelLarge` đậm 600. Không đặt lại `CircleBorder` ở theme hay từng màn (nút có chữ sẽ thành hình tròn, chữ tràn ra ngoài) |
| Số tin chưa đọc | `WebTuiUnreadBadge` / `webTuiUnreadLabel`: chat 1-1 (cả bot thông báo) hiện 1–5 rồi `5+`; nhóm / kênh hiện 1–99 rồi `99+`. Web dùng cùng trần (`unread-badge.ts`) |
| Dòng tin chưa đọc | Hội thoại còn tin chưa đọc: dòng tin cuối đậm 700, màu `textPrimary` (thường: 400, `textSecondary`), giờ màu `primary` đậm 700. Không chỉ dựa vào số đỏ để báo chưa đọc |
| Chip chọn có icon | `ChoiceChip` / `FilterChip` có `avatar` phải đặt `showCheckmark: false`: để mặc định thì lúc chọn Flutter phủ vòng tối lên icon (trông như lỗi hover). Màu nền chip đã đủ báo đang chọn |
| Menu ấn giữ hội thoại | Ấn giữ một dòng chat mở menu nổi ngay tại dòng đó (`showConversationQuickActions`), thay cho nút ba chấm trên web: canh phải, ngay dưới dòng; không đủ chỗ (chừa thanh tab nổi) thì bật lên phía trên. Rộng 240, bo 12, nền `surface`, bóng mềm (elevation 6, bóng đen 22%; nền tối 60% + viền trắng 8%), không viền ở nền sáng. Dòng chữ cỡ 15.5 cao 48, không icon. Dòng đang mở menu tô nền như đang chọn. Xoá / rời / báo xấu ở cuối, có kẻ mảnh ngăn; chữ xoá / rời màu `danger` (nền sáng làm đậm thêm 20% cho đủ tương phản). Ghim / chưa đọc / ẩn lưu trên máy; kênh nghiệp vụ chỉ có đánh dấu đã đọc / chưa đọc |
| Gọi tên "nhóm" | Chữ trên giao diện gọi kênh chat là **nhóm** (EN: group), không dùng "kênh". Chỉ giữ "kênh" cho kênh nghiệp vụ / bot có phiên riêng và kênh bán hàng của hộp thư khách (Zalo, Facebook) |

## Quy tắc kiểm tra UI

- Không dựng hero marketing làm màn đầu.
- Không dùng palette một màu quá nặng; vẫn giữ nền sáng và primary xanh.
- Không nhồi card trong card.
- Không để text tràn khỏi chip, tab, list item hoặc button.
- Không dùng tiếng Việt không dấu trong UI.
- Màn auth (đăng nhập, đăng ký, xác minh...) không cứng màu: nền, ô nhập, nút, chữ lấy từ `WebTuiColors` / theme để chữ đạt 4,5:1 cả sáng lẫn tối (test `login_screen_test.dart`).
- Khung chat co theo bàn phím: danh sách đang ở cuối thì giữ ở cuối khi bàn phím mở / đóng, đang đọc tin cũ thì không cuộn (test `chat_room_keyboard_scroll_test.dart`).
- Screenshot Flutter trên iPhone-like và Android-like viewport phải đặt cạnh ảnh reference để review.
- Màn chat, danh bạ, kênh/bot và cài đặt phải thể hiện được cùng tinh thần với reference trước khi bước sang polish.


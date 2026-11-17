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
| Danh bạ Bạn bè (kiểu Zalo) | Không tiêu đề lớn: ô tìm ngay dưới thanh trạng thái, dưới là thanh tab gạch chân Đồng nghiệp / Nhóm (chữ đậm 15, số đếm nhỏ cạnh chữ, gạch `primary` ở tab chọn, cao 44). Đồng nghiệp xếp A–Z theo chữ cái đầu sau khi bỏ dấu ("Đức" → D, "Ánh" → A; số / ký tự lạ → `#` ở cuối), tiêu đề nhóm chữ cái đậm nhỏ, nền trùng nền danh sách, dính khi cuộn (`ContactLetterHeader`; hàm xếp `groupContactsAlphabetically`). Dòng: ảnh tròn 48 + tên 1 dòng; email chỉ hiện làm dòng phụ nhỏ mờ khi trùng tên. Cuối dòng 2 nút biểu tượng `call_outlined` / `videocam_outlined` màu chữ phụ, vùng bấm 44, tooltip "Gọi thoại" / "Gọi video"; bấm mở chat riêng với `startCall=audio|video`. Người bị chặn / chưa mở được chat riêng không có nút gọi |
| Ô ứng dụng (tab Công việc) | Ô vuông 52 bo 14, mỗi ứng dụng một màu riêng (bảng `workAppBlue/Orange/Green/Violet/Red/Teal/Gray`), tính bằng `workAppTileColors`. **Nền sáng:** ô pastel phẳng gần trắng (màu riêng 7% → 12% trên trắng), không bóng; biểu tượng Material rounded 26 mang màu riêng, tươi hơn và sáng tới mức nhạt nhất còn tương phản ≥ 3:1 với nền ô. **Nền tối:** gradient đậm của màu riêng (đầu trên trái sáng hơn, cuối dưới phải đậm hơn, cả hai tương phản ≥ 3:1 với trắng), biểu tượng trắng, bóng rất nhẹ. Nhãn 12, tối đa 2 dòng, căn giữa, màu chữ theme. Ô Thêm (viền đứt, `add_rounded`): nền sáng là nền xanh chủ đạo rất nhạt (5%), viền và biểu tượng `primary`; nền tối là nền `surface`, viền và biểu tượng màu chữ mờ. Không dùng biểu tượng hai lớp Phosphor trong lưới này |
| Khung phòng chat (kiểu Zalo) | Thanh đầu: nền sáng = `primary` gradient nhẹ sang phải, tên / trạng thái / nút quay lại / gọi thoại / gọi video / ≡ màu trắng, thanh trạng thái hệ thống icon sáng; nền tối = `surface` tối, chữ / icon sáng (không xanh chói). Nền danh sách `chatBackground` (sáng `#E2E9F1`). Bong bóng: của mình `messageOutgoing` (sáng `#D9E8FF` + viền `messageOutgoingBorder`; tối `#1B4478`), của người khác `messageIncoming`; chữ luôn `textPrimary` (không dùng `textOnPrimary` trong bong bóng), liên kết / nhắc tên của mình: `primaryPressed` (tối: trắng); bo 16, góc dưới phía người gửi 4. Ô soạn: [emoji] [ô nhập không viền] [⋯ đính kèm] [ảnh] [mic]; có chữ / tệp chờ gửi thì ảnh + mic nhường chỗ cho nút gửi (`primary`); mọi nút ≥ 44, có tooltip. Test `chat_room_zalo_style_test.dart` |
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


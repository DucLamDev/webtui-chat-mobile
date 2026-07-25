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
| Tin nhắn | Màn mặc định sau đăng nhập | Header "Tin nhắn", icon nhỏ, segmented tabs, search, danh sách hội thoại |
| Bạn bè | Danh bạ và kênh/bot tích hợp | Tab "Hội thoại" và "Kênh & Bot", list item dày, trạng thái chưa đọc |
| Kênh | Danh sách channel theo workspace | Search/settings, channel category, badge trạng thái tham gia/mở kênh |
| Cài đặt | Profile và thiết lập WebTui nâng cao | Avatar lớn, tên user, card setting, toggle, slider, bottom tab active |

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
| Segmented tabs | Dùng cho Hội thoại/Kênh & Bot, Tất cả/Chưa đọc/Yêu thích |
| Icon | Dùng icon mềm, quen thuộc, không dùng icon cứng/AI-looking |

## Quy tắc kiểm tra UI

- Không dựng hero marketing làm màn đầu.
- Không dùng palette một màu quá nặng; vẫn giữ nền sáng và primary xanh.
- Không nhồi card trong card.
- Không để text tràn khỏi chip, tab, list item hoặc button.
- Không dùng tiếng Việt không dấu trong UI.
- Screenshot Flutter trên iPhone-like và Android-like viewport phải đặt cạnh ảnh reference để review.
- Màn chat, danh bạ, kênh/bot và cài đặt phải thể hiện được cùng tinh thần với reference trước khi bước sang polish.


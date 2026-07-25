# Kiểm tra design system mobile với reference

Ảnh gốc trong monorepo:
`../../docs/design/mobile/references/webtui-mobile-zalo-reference.png`

Screenshot Flutter đã tạo:

- `test/screenshots/webtui_design_iphone_messages_device.png`: viewport iPhone-like 393x852, tab Tin nhắn.
- `test/screenshots/webtui_design_android_settings_device.png`: viewport Android-like 412x915, tab Cài đặt.

## Đối chiếu nhanh

- Màu: nền xám rất nhạt, surface trắng, primary xanh WebTui/Zalo-like cho tab active, badge và bubble gửi đi.
- Mật độ: item hội thoại cao 68px, avatar 44px, divider mảnh và nội dung preview chỉ một dòng để danh sách dày như reference.
- Navigation: bottom navigation 4 tab gồm Tin nhắn, Danh bạ, Khám phá, Thêm; icon mềm và nhãn ngắn.
- Filter: segmented tabs cao 34px, nền xám nhạt, selected surface trắng giống cụm filter trong ảnh.
- Cài đặt: setting row dạng list, toggle và slider gọn, không dùng card phình to kiểu marketing.
- Trạng thái: empty/loading/error state có khung nhỏ, dùng cho khu vực nội dung chứ không làm hero hoặc landing page.

Fixture trong màn preview chỉ phục vụ kiểm tra component và không tạo mock backend/repository cho production.

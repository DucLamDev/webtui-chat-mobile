# Luật duyệt riêng: webtui-chat-mobile

## Bảo mật riêng

- PR không được thêm vào repo kế hoạch, bản rà soát, thư trao đổi hay tài liệu giao thức của đội IDE: tệp `*.md`
  (hoặc tệp chữ khác) có nội dung đó, ảnh chụp các tài liệu đó. Repo này công khai; thấy thì trả về.
- PR không được thêm đường dẫn tuyệt đối trên máy của đội IDE (thư mục nhà, thư mục `.cache` hay thư mục làm việc
  của máy IDE) vào mã, test, tài liệu, chú thích.
- PR đổi một trong các phần sau thì mô tả PR phải có mục ghi rõ thay đổi phần IDE (làm gì, vì sao, ảnh hưởng tới
  bắt tay / khoá / kênh thế nào); thiếu thì trả về:
  - `lib/features/ide_mobile/**` phần kênh, bắt tay, khoá (`data/ide_channel*.dart`, `data/ide_connection.dart`,
    `data/ide_device_key_store.dart`, `data/ide_pair_api.dart`, `data/ide_rpc_client.dart`,
    `application/ide_pairing_service.dart`, `application/ide_step_up.dart`, `domain/ide_canonical_json.dart`,
    `domain/ide_device_credentials.dart`, `domain/ide_device_security.dart`);
  - `android/**/IdeDeviceSecurity.kt`;
  - phần IDE trong `ios/Runner/AppDelegate.swift` (`enum IdeDeviceSecurity`, khoá xác nhận, kênh `webtui/biometric`).

# Luồng mobile cho mô hình self-hosted

Ngày cập nhật: 2026-07-24

## Kết luận ngắn

Mobile nên đi theo mô hình một app native dùng chung cho nhiều server self-hosted,
giống nhóm sản phẩm open-source/self-hosted: người dùng nhập domain instance,
app discovery runtime/capability, rồi đăng nhập vào chính instance đó.

Nhập domain trong mobile không tạo server mới. Nếu muốn "nhập domain là tự dựng
server", cần thêm control plane/provisioner SaaS riêng. Với định hướng open-source
cho doanh nghiệp nhỏ, luồng đúng là:

```text
Admin cài instance trên VPS -> Người dùng nhập domain -> Mobile discovery -> Login -> Chat
```

## Luồng người dùng mobile

### 1. Mở app lần đầu

Màn đầu tiên phải hỏi địa chỉ server:

```text
chat.company.com
```

App chuẩn hóa input:

- `chat.company.com` -> `https://chat.company.com`
- chỉ cho `http://localhost:<port>` trong dev;
- không nhận path, query, fragment hoặc user/password trong URL.

### 2. Discovery

App gọi:

```http
GET https://chat.company.com/api/v1/discovery?domain=chat.company.com
```

Server hợp lệ phải trả discovery có:

- `runtime.api_base_url`
- `runtime.ws_base_url`
- `runtime.rtc_ice_servers`
- `capabilities`
- `zone.registration_mode`
- `workspace` mặc định nếu có

Nếu discovery lỗi, UX nên nói rõ đây là lỗi server/DNS/TLS, không phải sai tài
khoản. Ví dụ:

- "Không tìm thấy server VPSTTT Chat tại domain này."
- "TLS chưa sẵn sàng, hãy nhờ quản trị viên kiểm tra cài đặt."
- "Server trả discovery không hợp lệ."

### 3. Login/register

Sau discovery, app lưu `api_base_url` và `ws_base_url` vào secure storage; mọi
request auth và kết nối realtime đi tới instance đó:

```text
POST /api/v1/auth/login
POST /api/v1/auth/register
POST /api/v1/auth/refresh
POST /api/v1/auth/logout
```

Domain không phải dữ liệu đăng ký tenant trong mobile. Domain chỉ chọn server.
Backend self-host dùng `INSTANCE_DOMAIN` canonical của chính instance, không tin
domain do client gửi trong body. Tài khoản đầu tiên trên instance self-hosted
trở thành owner; các tài khoản sau đi theo `invite_only` nếu backend đã khóa
đăng ký mở.

### 4. Sau đăng nhập

App tải:

- session user;
- workspace mặc định hoặc danh sách workspace được tham gia;
- permission/RBAC;
- conversation list;
- sync cursor;
- push device registration nếu push được cấu hình.

WebSocket kết nối tới `runtime.ws_base_url`, không hard-code host build-time.

## Luồng cài đặt của customer

Mobile chỉ hoạt động sau khi admin đã cài server:

1. Admin chuẩn bị VPS, DNS và firewall.
2. Admin chạy `deploy/self-hosted/install.sh`.
3. Admin mở `https://chat.vpsttt.com/portal` và nhập `chat.company.com`.
4. Portal discovery rồi chuyển admin tới trang tạo tài khoản owner đầu tiên.
5. Admin gửi domain hoặc QR cho nhân viên.
6. Nhân viên cài app, nhập `chat.company.com`, đăng nhập hoặc đăng ký bằng lời mời.

Với doanh nghiệp nhỏ, flow này dễ giải thích hơn flow SaaS claim domain vì dữ
liệu và hạ tầng đều nằm trong server của customer.

## Deep link và lời mời

Không nên phụ thuộc hoàn toàn vào Universal Links/App Links trên domain bất kỳ.
Lý do: mỗi customer có domain riêng, mobile app store build không thể biết trước
tất cả domain để khai báo entitlement/association.

Khuyến nghị:

- MVP: admin gửi domain và invite token; người dùng nhập domain trong app.
- Tốt hơn: web admin tạo QR chứa server + invite token, mobile scan để điền sẵn.
- Có thể dùng custom scheme:

```text
webtui://connect?server=https%3A%2F%2Fchat.company.com&invite=...
```

Custom scheme không bảo mật bằng verified app link, nên token invite phải ngắn
hạn, một lần dùng và luôn verify lại trên server.

Nếu muốn verified App Links/Universal Links cho từng domain customer, mỗi
instance phải phục vụ file association phù hợp và app phải có entitlement tương
ứng. Điều này không thực tế cho một app public dùng cho mọi domain.

## Push notification: phần khó nhất

Foreground realtime dùng WebSocket nên đơn giản. Khi app background hoặc bị OS
kill, Android/iOS cần FCM/APNs.

Có ba hướng sản phẩm:

| Hướng | Phù hợp | Đổi lại |
|---|---|---|
| Official mobile app dùng chung, không push relay | Open-source/self-host thuần, dễ phát hành | Notification nền hạn chế; app phải catch-up khi mở lại |
| Official app + VPSTTT push relay tối thiểu | UX tốt cho SME, không cần customer build app | Có dịch vụ trung tâm nhận metadata/token; phải thiết kế privacy rõ |
| Customer tự build/branded app với Firebase/APNs riêng | Self-host tuyệt đối, push đầy đủ | Khó cho SME; cần tài liệu build/signing/Firebase |

Repo hiện có foundation `push_devices`, notification worker và Firebase config.
Để self-host thuần hoạt động đầy đủ, customer phải cung cấp Firebase service
account tương ứng với app họ cài. Nếu dùng một app official trên CH Play/App
Store, không nên phát tán service account của Firebase project đó cho mọi
customer. Khi đó cần push relay hoặc chấp nhận push nền là giới hạn của bản
self-host.

Khuyến nghị cho MVP doanh nghiệp nhỏ:

1. Android-first: phát APK signed hoặc app store chung, nhập domain để đăng nhập.
2. Chat, file, sync, WebSocket hoạt động đầy đủ khi app mở.
3. Push nền ghi rõ là "cần cấu hình Firebase/push relay" trước khi cam kết SLA.
4. Dùng sync cursor làm nguồn khôi phục bắt buộc khi app mở lại.

## SSO/OIDC trên mobile

Native Google Sign-In build-time không phù hợp làm cơ chế chung cho mọi server
self-hosted, vì mỗi customer có cấu hình IdP/client khác nhau.

Luồng nên dùng:

1. App nhập domain và discovery.
2. App gọi `GET /api/v1/auth/oidc/providers?domain=chat.company.com`.
3. Nếu có provider, hiển thị nút "Đăng nhập SSO".
4. App mở system browser bằng authorization-code + PKCE.
5. Callback về custom scheme hoặc completion code.
6. App gọi `/api/v1/auth/oidc/complete` trên instance đã chọn.

Mật khẩu vẫn là đường MVP đơn giản nhất. Google native button hiện chỉ nên coi
là tùy chọn cho build/instance được cấu hình rõ, không phải luồng SSO mặc định
của self-host.

## Server switch và bảo vệ dữ liệu

Mobile phải coi mỗi server là một ranh giới dữ liệu:

- đổi server phải logout hoặc yêu cầu xác nhận;
- xóa access token, refresh token, workspace id, WebSocket subscription;
- cache local phải scope theo server + workspace;
- draft/outbox không được gửi nhầm sang server khác;
- deep link phải khớp server hiện tại hoặc yêu cầu chuyển server trước.

MVP có thể chỉ hỗ trợ một server active tại một thời điểm. Multi-account/multi-
server là P1.

## Refactor đã chốt trong code

- `RegisterUseCase` không còn nhận hoặc validate domain như dữ liệu đăng ký.
- `AuthRemoteDataSource.register` không gửi `domain` trong body; backend tự lấy
  zone từ Host.
- Login controller vẫn bắt buộc nhập địa chỉ server trước khi login/register.
- Discovery được parse bằng model typed và kiểm tra domain, trạng thái zone,
  trạng thái deployment, capability self-hosted, HTTPS/WSS và cùng hostname.
- Login controller lưu cả `runtime.api_base_url` và `runtime.ws_base_url` vào
  secure storage; realtime dùng WebSocket URL đang active.
- UI chặn đăng ký mở khi server trả `registration_mode=invite_only|closed`.
- Khi discovery sang server khác thành công, app xóa token, workspace và cache
  phiên cũ trước khi kích hoạt runtime mới.
- UI auth đổi label từ "Domain server" sang "Địa chỉ server".

## Refactor tiếp theo nên làm

1. Tách màn "Chọn server" thành bước riêng trước login/register.
2. Lưu đầy đủ discovery snapshot gồm capabilities và RTC ICE, không chỉ API/WS.
3. Ẩn/hiện SSO theo `/auth/oidc/providers`, không hiện Google button mặc định.
4. Thêm scan QR server/invite.
5. Bổ sung UI xác nhận server switch và hỗ trợ multi-account/multi-server.
6. Chốt chiến lược push: không push nền, push relay, hoặc customer-branded build.

## Acceptance cho mobile self-host MVP

- Nhập domain của instance đã cài thì discovery pass.
- Domain chưa cài hoặc TLS lỗi trả thông báo dễ hiểu.
- Login/register không gửi tenant/domain tùy ý trong body.
- Access/refresh token chỉ dùng với server đã chọn.
- WebSocket dùng runtime của discovery.
- Logout xóa token và unregister push device nếu có.
- App resume sau offline/background chạy sync catch-up.
- Không có dữ liệu workspace/server này xuất hiện ở server khác.

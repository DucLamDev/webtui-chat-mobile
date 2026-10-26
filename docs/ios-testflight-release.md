# Phát hành iOS: TestFlight và App Store bằng GitHub Actions

Job `ios-release` trong `.github/workflows/mobile.yml` chạy trên máy macOS của GitHub (không cần Mac riêng). Khi đẩy tag
`mobile-vX.Y.Z`, job sẽ:

1. Build IPA bản production đã ký: phiên bản `X.Y.Z`, số build = `số lần chạy workflow × 100 + lần thử`.
2. Đẩy lên **TestFlight** và chờ Apple xử lý xong (`ios/fastlane/Fastfile`, lane `upload_testflight`).
3. Nếu bật `IOS_SUBMIT_FOR_REVIEW=true`: gắn bản build vào phiên bản `X.Y.Z` trên App Store Connect, điền "Có gì mới" rồi
   **gửi duyệt App Store** (lane `submit_review`). Duyệt xong thì phát hành tự động nếu `IOS_AUTOMATIC_RELEASE=true`,
   nếu không thì bấm phát hành tay.

Job chỉ chạy khi biến `ENABLE_IOS_RELEASE=true` và job `verify` (format, analyze, test) đạt.

## 1. Chuẩn bị bên Apple (làm một lần)

### 1.1. App ID và app trên App Store Connect

- developer.apple.com → Certificates, Identifiers & Profiles → **Identifiers**: App ID `com.vpsttt.webtuiChat`, bật
  **Push Notifications** và **Associated Domains**. App cần cả hai (`ios/Runner/Runner.entitlements`).
- appstoreconnect.apple.com → **Apps** → tạo app với bundle ID trên. Mã Team ID (10 ký tự) xem ở developer.apple.com →
  Membership.

### 1.2. Chứng chỉ Apple Distribution → file `.p12` (làm được trên Linux)

```bash
openssl genrsa -out dist.key 2048
openssl req -new -key dist.key -out dist.csr -subj "/emailAddress=<email Apple ID>/CN=VPSTTT/C=VN"
# developer.apple.com → Certificates → + → Apple Distribution → tải dist.csr lên → tải về distribution.cer
openssl x509 -in distribution.cer -inform DER -out dist.pem -outform PEM
# -legacy: macOS (security import) không đọc được .p12 kiểu mã hoá mặc định của OpenSSL 3.
openssl pkcs12 -export -legacy -inkey dist.key -in dist.pem -out dist.p12 -passout pass:'<mật khẩu .p12>'
base64 -w0 dist.p12 > dist.p12.base64
```

Trên Mac thì xuất `.p12` từ Keychain Access, rồi `base64 -i dist.p12 | pbcopy`.

### 1.3. Provisioning profile App Store

developer.apple.com → **Profiles** → + → **App Store Connect** → chọn App ID `com.vpsttt.webtuiChat` và chứng chỉ ở bước
1.2 → đặt tên (vd. `WebTUI Chat App Store`) → tải file `.mobileprovision`:

```bash
base64 -w0 WebTUI_Chat_App_Store.mobileprovision > profile.base64
```

Tạo lại profile mỗi khi đổi chứng chỉ hoặc bật thêm capability cho App ID.

### 1.4. App Store Connect API key

appstoreconnect.apple.com → **Users and Access** → **Integrations** → **App Store Connect API** → Team Keys → + →
quyền **App Manager** → tải file `AuthKey_<KEY_ID>.p8` (chỉ tải được một lần). Ghi lại **Key ID** và **Issuer ID** (hiện
ở đầu trang).

```bash
base64 -w0 AuthKey_<KEY_ID>.p8 > asc_key.base64
```

Sau khi đưa lên GitHub, xoá các file `dist.key`, `.p12`, `.p8`, `*.base64` trên máy hoặc cất vào kho bí mật của công ty.

## 2. Cấu hình GitHub

GitHub repo → **Settings** → **Environments** → **production** (tạo nếu chưa có; nên bật *Required reviewers* để mỗi lần
phát hành phải có người duyệt).

### 2.1. Secrets (Environment secrets của `production`)

| Tên | Giá trị |
|---|---|
| `APPLE_DISTRIBUTION_CERT_P12_BASE64` | nội dung `dist.p12.base64` |
| `APPLE_DISTRIBUTION_CERT_PASSWORD` | mật khẩu `.p12` |
| `APPLE_PROVISIONING_PROFILE_BASE64` | nội dung `profile.base64` |
| `APPSTORE_CONNECT_API_KEY_ID` | Key ID |
| `APPSTORE_CONNECT_API_ISSUER_ID` | Issuer ID |
| `APPSTORE_CONNECT_API_PRIVATE_KEY_BASE64` | nội dung `asc_key.base64` |
| `MOBILE_FIREBASE_API_KEY` | giá trị `FIREBASE_API_KEY` trong lệnh build (`ios.txt`) |

### 2.2. Variables (Environment variables của `production`)

Lấy giá trị từ các `--dart-define` trong `ios.txt` (cùng giá trị server đang dùng):

| Biến GitHub | Lấy từ |
|---|---|
| `MOBILE_REFERENCE_INSTANCE_URL` | `WEBTUI_API_BASE_URL` |
| `MOBILE_PRIVACY_POLICY_URL` | `WEBTUI_PRIVACY_POLICY_URL` |
| `MOBILE_TERMS_URL` | `WEBTUI_TERMS_URL` |
| `MOBILE_TERMS_VERSION` | `WEBTUI_TERMS_VERSION` |
| `MOBILE_PRIVACY_VERSION` | `WEBTUI_PRIVACY_VERSION` (phải bằng `MOBILE_TERMS_VERSION`) |
| `MOBILE_ACCOUNT_DELETION_URL` | `WEBTUI_ACCOUNT_DELETION_URL` |
| `MOBILE_SUPPORT_URL` | `WEBTUI_SUPPORT_URL` |
| `MOBILE_FIREBASE_IOS_APP_ID` | `FIREBASE_IOS_APP_ID` |
| `MOBILE_APP_LINK_HOST` | `chat.vpsttt.com` |
| `APPLE_TEAM_ID` | Team ID 10 ký tự |
| `APPLE_PROVISIONING_PROFILE_NAME` | đúng tên profile ở bước 1.3 |
| `ENABLE_IOS_RELEASE` | `true` |
| `IOS_SUBMIT_FOR_REVIEW` | `false` lần đầu; `true` khi muốn tự gửi duyệt (mục 3) |
| `IOS_AUTOMATIC_RELEASE` | `true`: duyệt xong tự lên App Store; `false`: phát hành tay |
| `IOS_RELEASE_NOTES` | "Có gì mới" cho bản sắp phát hành (để trống: "Cải thiện hiệu năng và sửa lỗi.") |

Không cần đặt: `WEBTUI_APP_VERSION` / số phiên bản (lấy từ tag), `WEBTUI_RELEASE_CHANNEL`, `WEBTUI_RELEASE_SERVICE_URL`,
`FIREBASE_MESSAGING_SENDER_ID`, `FIREBASE_PROJECT_ID` (đã cố định trong workflow, trùng `ios.txt`).

### 2.3. Server

Workflow kiểm tra `https://chat.vpsttt.com/.well-known/apple-app-site-association` phải trả **200** và cho phép
`<APPLE_TEAM_ID>.com.vpsttt.webtuiChat`. Caddy của chat chuyển đường dẫn này sang portal `download.webtui.vn`, nên `.env`
của **portal** cần `ENABLE_IOS_ASSOCIATION=true`, `APPLE_TEAM_ID=<Team ID>`, `APPLE_BUNDLE_ID=com.vpsttt.webtuiChat`,
sau đó deploy lại portal. Kiểm tra:

```bash
curl -i https://chat.vpsttt.com/.well-known/apple-app-site-association
```

## 3. Phát hành

1. Tăng `version` trong `pubspec.yaml` (nếu cần), merge vào `master`.
2. Tạo tag và đẩy lên:

   ```bash
   git tag mobile-v1.0.1 && git push origin mobile-v1.0.1
   ```

3. Theo dõi tab **Actions** → *Mobile CI and release* → job `ios-release` (thường 20–40 phút, phần lớn là chờ Apple xử
   lý build).

**Lần phát hành App Store đầu tiên**: để `IOS_SUBMIT_FOR_REVIEW=false`. Build lên TestFlight xong, vào App Store Connect
điền một lần các mục Apple bắt buộc: ảnh chụp màn hình, mô tả, từ khoá, URL hỗ trợ / chính sách, App Privacy, xếp hạng tuổi,
thông tin liên hệ và **tài khoản demo cho người duyệt**, rồi bấm gửi duyệt. Từ phiên bản sau, đặt
`IOS_SUBMIT_FOR_REVIEW=true`: mỗi tag mới sẽ tự gửi duyệt với "Có gì mới" lấy từ `IOS_RELEASE_NOTES`; mô tả, ảnh trên App
Store Connect giữ nguyên.

## 4. Lỗi thường gặp

| Hiện tượng | Cách xử lý |
|---|---|
| `security import` báo *MAC verification failed* | Tạo lại `.p12` với `-legacy` (mục 1.2). |
| *No profile for team … matching …* / *doesn't include signing certificate* | Profile không chứa chứng chỉ đang dùng hoặc `APPLE_PROVISIONING_PROFILE_NAME` sai tên: tạo lại profile, cập nhật secret và biến. |
| *Provisioning profile doesn't support Push Notifications / Associated Domains* | Bật capability cho App ID rồi tạo lại profile. |
| Bước *Validate public production endpoints* lỗi apple-app-site-association | Xem mục 2.3. |
| *The bundle version must be higher* | Số build đã dùng: chạy lại workflow (số build tăng theo lần chạy). |
| Build kẹt *Missing Compliance* | Trả lời câu hỏi mã hoá trên App Store Connect, hoặc khai báo `ITSAppUsesNonExemptEncryption` trong `ios/Runner/Info.plist` sau khi đã xác định đúng. |
| Gửi duyệt báo thiếu thông tin | Bổ sung mục còn thiếu trên App Store Connect (mục 3), chạy lại job. |

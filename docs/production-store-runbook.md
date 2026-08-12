# Quy trình đưa WebTUI Chat lên production và store

Tài liệu này là thứ tự phát hành bắt buộc cho release đầu tiên có moderation,
legal acceptance và account deletion. Không upload AAB/IPA trước khi backend và
portal production đã vượt qua toàn bộ public endpoint gate.

Với kiến trúc self-host, đọc thêm contract chuẩn tại
`docs/self-hosted-store-release.md`: một binary dùng chung, customer nhập domain
thủ công, còn URL API dưới đây là reference/reviewer instance của publisher.

## Cần deploy những thành phần nào?

- Một release mobile thông thường chỉ cần upload binary mobile nếu API hiện tại
  vẫn tương thích và không có migration/backend feature mới.
- Google Play chỉ nhận AAB. Backend/database customer được mỗi operator deploy
  riêng; publisher không upload chúng cùng mobile và không build AAB theo customer.
- Publisher vẫn phải giữ reference/reviewer instance, portal/policies và relay
  (nếu bật push official) online trong review và rollout.
- **Release này phải deploy backend trước** vì mobile mới phụ thuộc legal
  documents, moderation report, block/unblock và enforcement trong message/call.
- **Portal phải deploy riêng** để cung cấp Privacy, Terms, Acceptable Use,
  Support, Account Deletion và hai association file. Portal không phải service
  trong compose self-host.
- Sau khi backend và portal đã public/healthy mới build binary production. Một
  AAB/IPA đã nhúng sai URL/Firebase/app ID phải build lại, không sửa được trong
  Play Console/App Store Connect.

## Thứ tự phát hành

### 1. Chốt định danh vĩnh viễn

- Android package: `com.vpsttt.webtui_chat`.
- iOS bundle ID: `com.vpsttt.webtuiChat`.
- Reference/reviewer API: `https://chat.vpsttt.com`.
- Publisher-controlled App/Universal Link host: `chat.vpsttt.com`; customer
  domains được nhập thủ công và không cần association file của official app.
- Portal/policy origin: `https://download.webtui.vn`.
- Legal version của portal phải khớp chính xác version backend trả tại
  `/api/v1/auth/legal-documents`.
- `MOBILE_TERMS_VERSION` và `MOBILE_PRIVACY_VERSION` phải khớp version hiển thị
  trên hai policy page; release gate đối chiếu cả ba nguồn trước khi build.

Không đổi package/bundle ID sau khi đã tạo store record nếu mục tiêu là cập nhật
cùng một app.

### 2. Chuẩn bị external state

Người sở hữu hệ thống phải cung cấp:

- Play developer account, Play App Signing certificate SHA-256 và Android
  upload keystore;
- pháp nhân, địa chỉ, quốc gia, retention/deletion SLA và inbox thật cho
  support/privacy/safety;
- Firebase Android/iOS client config, FCM service account; APNs/VoIP keys nếu
  phát hành iOS;
- DNS/TLS và quyền deploy `chat.vpsttt.com`, `download.webtui.vn`;
- reviewer workspace với một tài khoản chính không OTP và một tài khoản xóa
  thử riêng, không tài khoản nào chứa dữ liệu người dùng thật.

Secret chỉ đặt trong protected GitHub `production` environment hoặc secret
manager. Không commit `.env`, keystore, APNs key hay reviewer password.

### 3. Deploy portal và association files

Dùng `webtui-chat-portal/deploy/compose.yml` với `.env` production đã thay toàn
bộ `CHANGE_ME`. Sau deploy, năm URL public phải trả HTTP 200, TLS hợp lệ và
không yêu cầu đăng nhập:

```text
https://download.webtui.vn/privacy
https://download.webtui.vn/terms
https://download.webtui.vn/acceptable-use
https://download.webtui.vn/account-deletion
https://download.webtui.vn/support
```

Với CH-Play, URL Android sau phải trả trực tiếp HTTP 200, JSON đúng, không
redirect:

```text
https://chat.vpsttt.com/.well-known/assetlinks.json
```

`assetlinks.json` phải chứa Play **app-signing** SHA-256, không phải upload-key
SHA-256. Khi chỉ phát hành CH-Play, portal phải đặt
`ENABLE_IOS_ASSOCIATION=false`, để trống Apple Team/Bundle ID và AASA trả 404
fail-closed. Chỉ trước khi phát hành iOS mới đổi flag thành `true`; lúc đó
`https://chat.vpsttt.com/.well-known/apple-app-site-association` phải trả 200 và
chứa đúng `APPLE_TEAM_ID.com.vpsttt.webtuiChat`.

Với app mới chưa có Play SHA, chạy thủ công **Actions > Mobile CI and release >
Run workflow**, nhập SemVer vào `bootstrap_version` và nhập chính xác
`INTERNAL_ONLY_DO_NOT_PROMOTE` vào trường xác nhận. Job
`android-play-signing-bootstrap` dùng upload keystore vĩnh viễn, vẫn kiểm tra API
36/signature/manifest/symbol/alignment, nhưng được phép thiếu Play fingerprint và
không probe association endpoint. Nó không upload Play tự động; artifact có nhãn
`INTERNAL-ONLY`, retention 7 ngày và chỉ được upload thủ công vào Internal testing.

Copy Play App Signing SHA-256 sau lần upload đó, redeploy association file, set
GitHub variable, verify lại, rồi tạo tag để sinh versionCode mới và build AAB mới
qua toàn bộ gate. Không dùng upload fingerprint để lấp chỗ trống và không promote
AAB bootstrap sang Closed/Open/Production.

### 4. Deploy backend cùng web/admin

Portal phải public trước khi hệ thống bắt đầu thu consent. Sau đó:

1. Backup PostgreSQL và kiểm tra restore trước khi migrate.
2. Deploy image/version đã test cùng migrations
   `000039_ugc_moderation_and_legal_acceptance` và
   `000040_guest_legal_acceptance_evidence`; deploy web/admin cùng release để tài
   khoản cũ có UI chấp thuận, guest public có bằng chứng consent và moderator có
   queue xử lý report.
3. Chạy health/readiness, kiểm tra worker, Redis, RabbitMQ, storage và TURN.
4. Xác minh bằng hai tài khoản thường ở ít nhất hai workspace và một moderator:
   - đăng ký chỉ thành công khi accept đúng legal versions;
   - tài khoản cũ được hỏi consent riêng theo workspace, không backfill;
   - report message/user tạo item trong moderation queue;
   - moderator review/resolve và có audit event;
   - block theo một trong hai chiều chặn DM/direct-channel/call;
   - unblock khôi phục tương tác;
   - account deletion thu hồi session/device/token đúng policy.

Không chạy migration down trên dữ liệu production chỉ để rollback app. Khi có
sự cố, pause rollout, rollback service về bản tương thích schema và giữ backup
cho tới khi có kế hoạch dữ liệu được duyệt.

### 5. Cấu hình và build Android

Điền toàn bộ variables/secrets trong `docs/release-credentials.md`, bảo vệ
GitHub environment `production`, rồi tạo tag dạng `mobile-v1.0.0`. Workflow chỉ
publish artifact khi các gate sau cùng pass:

- format, architecture check, static analysis và unit/widget tests;
- public API/policy/app-link probes;
- release signing fail-closed;
- merged-manifest least privilege/API 36;
- APK 16 KB ZIP alignment và ELF segment alignment;
- AAB signature, native debug symbols và SHA-256 checksums.

Để release CH Play không bị phụ thuộc credential Apple chưa có, job iOS chỉ chạy
khi repository variable `ENABLE_IOS_RELEASE_CHECK=true`. Đây không phải cách bỏ
qua gate App Store: khi phát hành iOS phải bật lại và hoàn tất bước 7 bên dưới.

Artifact đưa lên Play là `app-prod-release.aab`; APK do CI ký bằng upload key chỉ
dùng cho kiểm tra trong job và không được lưu/phát hành bởi workflow Play-first.
Không public APK đó khi Play dùng app-signing key khác.
Fallback public phải là universal APK xuất từ Play (hoặc đã chứng minh có đúng
cùng app-signing certificate). Không upload artifact được ký bằng debug/test key.

### 6. Google Play tracks

1. Tạo app record với package vĩnh viễn và bật Play App Signing.
2. Hoàn thành Store Listing, App Content, Content Rating, Data Safety,
   foreground-service/full-screen-intent declarations, privacy/deletion URLs.
3. Điền reviewer account từ template an toàn, không commit credential.
4. Upload AAB vào Internal testing; chạy pre-launch report và device matrix.
5. Nếu là personal developer account tạo sau 13/11/2023, chạy Closed testing
   với tối thiểu 12 tester duy trì opt-in liên tục 14 ngày trước khi xin quyền
   Production; kiểm tra lại yêu cầu hiện hành ngay trong Play Console.
6. Bản Production đầu tiên không hỗ trợ rollout theo phần trăm. Chỉ phát hành
   sau khi crash/ANR, call, push, report/block/deletion và app links đều xanh;
   kiểm soát phạm vi bằng testing và quốc gia/khu vực nếu cần, đồng thời chỉ
   định người có quyền halt/unpublish. Từ các bản cập nhật sau, dùng staged
   rollout theo phần trăm với người có quyền pause/halt.

### 7. App Store nếu phát hành iOS

Windows/Linux chỉ kiểm được source và unsigned iOS build. IPA production cần
macOS/Xcode, Apple Distribution certificate, provisioning profile, App Store
Connect API key, APNs và VoIP entitlements. Trước TestFlight phải kiểm tra archive
thực, aggregated privacy report, Universal Links, CallKit/VoIP trên thiết bị vật
lý và toàn bộ App Privacy answers. Không submit App Store cho tới khi backend có
cơ chế lọc objectionable content trước khi đăng; report/block và human moderation
hiện tại chưa tự động đáp ứng riêng yêu cầu filtering của Apple Guideline 1.2.

## Điều kiện hoàn tất

Release chỉ được gọi là production khi có đủ bằng chứng:

- backend/portal public đúng version và restore procedure đã thử;
- CI release xanh, checksum và artifact được lưu;
- Play Internal/Closed hoặc TestFlight device tests xanh;
- reviewer account hoạt động và moderator xử lý report được;
- không còn placeholder legal/store metadata;
- store review approved; phạm vi quốc gia/khu vực của lần phát hành đầu, hoặc
  staged rollout của bản cập nhật sau, được theo dõi và không có blocker
  crash/ANR.

Source code có thể chuẩn bị mọi gate trên, nhưng việc deploy domain, tạo store
record, ký và bấm submit cần quyền của chủ tài khoản/server và không thể được giả
lập bằng credential placeholder.

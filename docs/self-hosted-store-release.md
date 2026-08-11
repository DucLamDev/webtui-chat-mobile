# Phát hành mobile production cho mô hình self-hosted

Tài liệu này là contract cấu hình bên ngoài cho binary store chính thức. Mô hình
phát hành là **one universal AAB**: publisher build, ký và upload đúng một package
`com.vpsttt.webtui_chat`; mỗi customer tự vận hành backend, database và domain rồi
người dùng nhập domain đó trong app. Không build AAB riêng cho từng customer.

## Ranh giới cần nhớ

| Thành phần | Ai vận hành | Có nằm trong AAB/Play Console không? |
| --- | --- | --- |
| Mobile binary, Firebase project, signing identity | Publisher | AAB chứa client và public Firebase client config; không chứa backend/service-account secret |
| Publisher portal, policy pages, support/deletion page | Publisher | Deploy web riêng, không upload cùng AAB |
| `reference/reviewer instance` | Publisher | Backend thật, luôn online để CI và Google reviewer kiểm tra |
| Push relay của official app | Publisher | Service riêng giữ FCM/APNs server credentials |
| Customer API, PostgreSQL, Redis, storage, moderation, backup | Customer/operator | Customer tự deploy; không upload lên Google Play |

`MOBILE_REFERENCE_INSTANCE_URL` là URL của instance do publisher kiểm soát, ví
dụ `https://chat.vpsttt.com`. Nó là default/fallback và target kiểm tra release,
không phải API trung tâm bắt buộc cho mọi user. Workflow vẫn truyền URL này vào
Dart qua tên tương thích `WEBTUI_API_BASE_URL`; repo variable cũ
`MOBILE_API_BASE_URL` chỉ là fallback migration. Sau discovery, API/WebSocket phải
dùng runtime URL của domain customer.

Một update chỉ đổi UI/client và vẫn tương thích contract có thể chỉ upload AAB.
Nếu app cần endpoint, migration, legal version hoặc push contract mới, deploy
backend/portal/relay tương thích trước, giữ backward compatibility trong thời
gian rollout, rồi mới promote mobile. Google Play không deploy backend thay bạn.

## App Links: chỉ host của publisher

Official manifest khai báo một `publisher-controlled App Link`, hiện là
`chat.vpsttt.com`. Android không thể thêm tùy ý domain customer vào manifest của
binary đã phát hành. Dynamic App Links Android 15+ chỉ thu hẹp/mở rộng rule dưới
host đã khai báo; nó không biến mọi domain self-host thành verified host.

- User nhập `chat.company.com` thủ công; app gọi discovery trên domain đó.
- Customer không cần phục vụ `assetlinks.json`/AASA cho official app.
- Chỉ publisher host phục vụ hai association file, HTTP 200 trực tiếp, không
  redirect và không authentication.
- `assetlinks.json` dùng SHA-256 của **Play App Signing key**, không dùng upload
  keystore. Nếu Play hiển thị nhiều signing certificate cần hỗ trợ, đưa tất cả
  fingerprint vào biến comma-separated theo hướng dẫn Console.
- Custom-branded app là sản phẩm khác: manifest host, package/bundle ID, signing
  identity, Firebase project, portal và association files đều phải thuộc bên build.

## Legal Policy Contract v1

Contract version 1 tách biệt với version nội dung policy (ví dụ `2026-08-07`):

1. Publisher công bố URL ổn định cho Terms, Privacy, Acceptable Use, Support và
   Account Deletion; Privacy nói rõ publisher và independent instance operator.
2. Mỗi instance tương thích trả `GET /api/v1/auth/legal-documents` với đúng hai
   document: `terms` gồm `terms_of_use`, `acceptable_use_policy`; `privacy` gồm
   `privacy_policy`. Version phải khớp policy publisher mà official app yêu cầu.
3. Registration gửi explicit Terms/Privacy acceptance; backend lưu immutable
   audit evidence. User hiện hữu được gate acceptance theo workspace/version.
4. Customer operator chịu trách nhiệm account, UGC, moderation, retention,
   backup và data-subject request trên instance. Publisher chịu trách nhiệm
   binary/SDK, portal, store listing và dữ liệu đi qua relay do publisher vận hành.
5. Khi policy đổi, cập nhật portal, backend versions, store disclosure và release
   variables trong cùng kế hoạch; không dùng giá trị mơ hồ như `latest`.

Privacy policy không được gọi mọi customer operator là “service provider” của
publisher nếu không có quan hệ và chỉ dẫn xử lý dữ liệu như vậy. Luồng xóa account
trong app phải xóa trên selected instance; public deletion URL phải cho user nhập
instance/account hoặc liên hệ đúng operator mà không buộc cài lại app.

## Firebase và push relay

Không đưa Firebase service account/APNs private key của official app cho customer.
Client chỉ chứa Firebase client identifiers; FCM registration token được đăng ký
với selected backend. Customer backend chuyển delivery tối thiểu qua relay bằng
token riêng, còn relay publisher mới gọi FCM/APNs.

Lấy identity bất biến của customer:

```sh
INSTANCE_DOMAIN=chat.company.com
curl -fsS "https://$INSTANCE_DOMAIN/api/v1/discovery?domain=$INSTANCE_DOMAIN" \
  | jq -er '.data.discovery.zone.id'
```

Customer `.env` khi dùng bundled Caddy của relay publisher:

```dotenv
PUSH_RELAY_URL=https://relay.publisher.example/push-relay/v1/deliveries
PUSH_RELAY_TOKEN=<unique-random-token-at-least-32-characters>
PUSH_RELAY_INSTANCE_ID=<exact-data.discovery.zone.id-uuid>

# Không cấu hình direct provider cho official binary.
FIREBASE_SERVICE_ACCOUNT_FILE=
FIREBASE_SERVICE_ACCOUNT_JSON_BASE64=
APNS_PRIVATE_KEY_FILE=
APNS_PRIVATE_KEY_BASE64=
```

Publisher relay `.env`:

```dotenv
PUSH_RELAY_SERVER_ENABLED=true
PUSH_RELAY_PUBLISHERS=<exact-zone-uuid>=<same-customer-token>
FIREBASE_PROJECT_ID=webtui-chat
FIREBASE_SERVICE_ACCOUNT_JSON_BASE64=<base64-service-account-json>

# Chỉ cần cho iOS release.
APNS_KEY_ID=<key-id>
APNS_TEAM_ID=<team-id>
APNS_BUNDLE_ID=com.vpsttt.webtuiChat
APNS_PRIVATE_KEY_BASE64=<base64-p8>
APNS_SANDBOX=false
```

Key trong `PUSH_RELAY_PUBLISHERS` phải giống chính xác `PUSH_RELAY_INSTANCE_ID`.
Worker inject identity đó vào body `instance_id`; relay dùng nó để chọn token,
rate-limit và partition job. Không dùng customer slug hoặc domain alias.

```sh
curl -sS -o /dev/null -w '%{http_code}\n' \
  https://relay.publisher.example/push-relay/v1/deliveries
# 405 = route tồn tại nhưng delivery chỉ nhận POST; 404 thường là sai prefix.
```

Giới hạn payload notification ở metadata cần thiết; không xem relay là “không thu
thập dữ liệu”. Đưa push token, device identifier và nội dung/preview thực tế vào
privacy inventory và Data Safety.

## Biến và secret release

GitHub environment `production` cần tối thiểu:

- Variables: `MOBILE_REFERENCE_INSTANCE_URL`, `MOBILE_APP_LINK_HOST`, các URL
  policy/support/deletion và legal versions, Firebase client identifiers,
  `PLAY_APP_SIGNING_SHA256_FINGERPRINTS`; Apple variables chỉ khi phát hành iOS.
- Secrets: Android upload keystore/password/alias/key password. FCM service
  account và APNs private key chỉ ở relay/secret manager, không phải dart-define.

Reference instance phải public, TLS hợp lệ, không chứa dữ liệu user thật và chạy
đúng backend contract. Publisher portal và relay cũng phải deploy độc lập trước
full release gate.

Nếu release đầu chỉ có CH-Play, portal dùng `ENABLE_IOS_ASSOCIATION=false` và để
trống `APPLE_TEAM_ID`/`APPLE_BUNDLE_ID`; AASA 404 là trạng thái chủ ý. Android
`assetlinks.json` vẫn luôn bắt buộc. Trước release iOS, bật flag, điền identity
Apple thật, redeploy portal rồi mới bật `ENABLE_IOS_RELEASE_CHECK=true`.

## Bootstrap Play App Signing lần đầu

App mới có chicken/egg: chưa upload bundle thì Play có thể chưa cấp App Signing
SHA-256, nhưng full gate cần fingerprint để kiểm tra `assetlinks.json`.

Đây là ngoại lệ duy nhất đối với nguyên tắc “deploy portal đầy đủ trước AAB”:
portal production cần fingerprint thật và một URL Play/Internal thật, nên có thể
chỉ deploy reference backend trước, tạo AAB bootstrap Internal, lấy Play App
Signing SHA-256 và URL track, rồi mới deploy portal đầy đủ. AAB bootstrap tuyệt
đối không được promote; AAB production phải có versionCode mới và vượt full gate.

Trước tiên mở **App integrity > App signing**. Nếu Console đã hiển thị App
signing key certificate thật thì bỏ qua toàn bộ bootstrap: cấu hình fingerprint,
deploy portal và chạy release tag bình thường. Chỉ dùng ngoại lệ dưới đây khi
fingerprint thực sự chưa được cấp.

Luồng ngoại lệ đã được tách thành job `android-play-signing-bootstrap`; không sửa
full release gate và không điền upload fingerprint giả vào biến production:

1. Tạo app record đúng package `com.vpsttt.webtui_chat`, chọn Play App Signing và
   cấu hình **upload keystore vĩnh viễn** trong GitHub environment `production`.
   Không tạo throwaway key: các lần upload sau phải tiếp tục dùng đúng upload key
   này, trừ khi hoàn tất quy trình reset upload key chính thức của Play.
2. Cấu hình mọi runtime variable ở `docs/release-credentials.md`, ngoại trừ
   `PLAY_APP_SIGNING_SHA256_FINGERPRINTS` vì giá trị này chưa tồn tại.
3. Trong GitHub chọn **Actions > Mobile CI and release > Run workflow**, nhập
   `bootstrap_version` dạng SemVer và nhập chính xác chuỗi xác nhận
   `INTERNAL_ONLY_DO_NOT_PROMOTE`. Chỉ workflow dispatch thủ công với chuỗi này
   mới chạy job bootstrap.
4. Job vẫn fail-closed đối với upload-key signing, Firebase/runtime config,
   target/compile API 36, merged manifest, AAB signature, native symbols và 16 KB
   alignment. Ngoại lệ duy nhất là chưa bắt buộc Play signing fingerprint và
   không probe public association endpoints. Job không có bước upload Play.
5. Download artifact có tên
   `android-play-signing-bootstrap-INTERNAL-ONLY-...` (retention 7 ngày), kiểm tra
   checksum, rồi upload thủ công file
   `app-prod-play-signing-bootstrap-INTERNAL-ONLY.aab` vào **Internal testing**.
   Không đưa release này sang Closed, Open testing hoặc Production.
6. Sau khi Play nhận bundle, mở **Test and release > App integrity > App signing**
   và copy SHA-256 của **App signing key certificate** dùng để ký APK giao tới
   thiết bị. Đây không phải SHA-256 của upload key.
7. Điền `PLAY_APP_SIGNING_SHA256_FINGERPRINTS`, redeploy publisher
   `assetlinks.json`, rồi chạy public endpoint checker và Play Deep Links tool.
8. Tạo tag `mobile-vX.Y.Z`. Workflow tag sinh **versionCode mới**, chạy full
   public association gate và xuất `app-prod-release.aab`. Chỉ AAB thứ hai này mới
   là ứng viên để promote. Google Play không nhận lại versionCode đã upload.

Bootstrap build là ngoại lệ có phạm vi hẹp để thiết lập signing identity; artifact
được phép promote phải là AAB versionCode mới sinh từ CI sau khi mọi gate xanh.

## Build AAB chính thức

1. Đảm bảo reference backend, portal/policies, association files và relay healthy.
2. Điền variables/secrets trong `docs/release-credentials.md`.
3. Chạy `dart run tool/check_mobile_release.dart` và test local phù hợp.
4. Tạo tag `mobile-vX.Y.Z`; protected workflow build prod, ký bằng upload key,
   kiểm tra public endpoints/signature/manifest/alignment và tạo
   `app-prod-release.aab` cùng checksum. Không build theo customer domain.
5. Upload AAB và native debug symbols vào Internal testing; cài từ Play để test
   đúng artifact được Play re-sign.

## Play Console: Data Safety, App Access và App Content

### Data Safety

- “Collected” gồm dữ liệu app/SDK truyền khỏi thiết bị, kể cả gửi tới server do
  user/customer chọn. Self-host không đồng nghĩa “không thu thập”.
- Khai báo theo hành vi tổng của package production: account/profile, user IDs,
  messages/UGC/files/media, app interactions/security audit, device/push token,
  relay/FCM/APNs và mọi SDK thực tế.
- Chỉ áp dụng E2EE exception khi publisher, operator và mọi intermediary đều
  không đọc được nội dung; HTTPS/TLS không phải E2EE.
- Đánh giá “shared” riêng cho independent operator, recipient và provider theo
  định nghĩa first party/service provider/user-initiated action; không tự động
  coi customer là service provider của publisher.
- Form, privacy policy và `store/google-play/data-safety.md` phải khớp artifact
  cùng cấu hình production ngay trước mỗi submission.

### App Access

Google reviewer phải dùng publisher-operated `reference/reviewer instance`, không
dựa vào một VPS customer có thể tắt. Điền hướng dẫn bằng tiếng Anh trong Console:

- domain phải nhập thủ công và URL discovery cụ thể;
- primary account reusable, không OTP/2FA/geo gate/password expiry;
- account thứ hai để reviewer test report/block và một deletion-test account;
- moderator account hoặc seeded evidence/instruction để thấy report được xử lý;
- workspace `Play Review` có seeded chat/file/call/settings, không dữ liệu thật;
- credentials hoạt động 24/7 trong toàn bộ review window.

### App Content

- UGC: Yes. User phải chấp nhận Terms/AUP trước khi tạo UGC; app có report
  content/user, block user và operator có moderation/action/audit vận hành thật.
- Account creation: Yes. Có in-app deletion và public web deletion resource.
- Restricted access: Yes. Điền App Access credentials, không commit vào git.
- Hoàn tất Content Rating, target audience, foreground-service/full-screen-intent
  declarations, privacy/deletion URLs và pre-launch report.

Sau Internal testing, chạy Closed testing nếu account yêu cầu. Personal developer
account tạo sau 13/11/2023 hiện phải có ít nhất 12 tester opt-in liên tục 14 ngày
trước khi xin Production access. Với thời điểm 2026, kiểm tra thêm developer
verification/package registration ngay trong Dashboard trước deadline áp dụng.

## Go/no-go

Chỉ promote khi reference instance và ít nhất một clean self-host test instance
đều pass discovery/login/legal/report/block/delete/sync/push; reviewer credentials
đã thử từ mạng ngoài; Data Safety khớp traffic; association dùng Play signing SHA;
pre-launch report không còn blocker crash/ANR/security; rollback backend và halt
rollout có owner rõ ràng.

## Nguồn chính thức

- [Google Play Data Safety](https://support.google.com/googleplay/android-developer/answer/10787469?hl=en)
- [Google Play User Data policy](https://support.google.com/googleplay/android-developer/answer/10144311?hl=en)
- [UGC policy](https://support.google.com/googleplay/android-developer/answer/9876937?hl=en)
- [Account deletion requirements](https://support.google.com/googleplay/android-developer/answer/13327111?hl=en)
- [App Access/sign-in details](https://support.google.com/googleplay/android-developer/answer/15748846?hl=en)
- [Play App Signing](https://support.google.com/googleplay/android-developer/answer/9842756?hl=en)
- [New personal account testing](https://support.google.com/googleplay/android-developer/answer/14151465?hl=en)
- [Android App Links](https://developer.android.com/training/app-links/configure-assetlinks)
- [Upload an AAB](https://developer.android.com/studio/publish/upload-bundle)
- [FCM trusted server environment](https://firebase.google.com/docs/cloud-messaging/server-environment)

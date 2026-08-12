# Android Internal Distribution

Phase M11 uses `.github/workflows/mobile.yml` for validation and signed Android artifacts.

## Required GitHub Secrets

Store these in the protected GitHub environment or repository secrets:

- `ANDROID_KEYSTORE_BASE64`: base64 content of the Android upload keystore.
- `ANDROID_KEYSTORE_PASSWORD`: keystore password.
- `ANDROID_KEY_ALIAS`: upload key alias.
- `ANDROID_KEY_PASSWORD`: upload key password.

Do not commit `android/key.properties`, `.jks`, or `.keystore` files. They are ignored by the mobile `.gitignore`.

## Release Artifacts

The release job builds:

- `app-prod-release.aab` for Google Play internal/closed tracks, plus its
  checksum/symbol evidence in the retained workflow artifact.
- An upload-key `app-prod-release.apk` only inside the runner for merged-manifest,
  alignment and installability checks; the Play-first workflow does not upload
  or publish it.

`versionCode` is `GITHUB_RUN_NUMBER * 10 + GITHUB_RUN_ATTEMPT`, so retries remain
unique. `versionName` comes from the semantic mobile tag.

The workflow does not retain or publish the APK. In the
recommended Play App Signing setup, CI signs with the upload key while Google
delivers APKs signed with a different app-signing key. Android cannot update an
install across those two certificates.

## Signature-safe public APK fallback

Prefer Play Internal/Closed testing. If a public/B2B APK fallback is genuinely
required, export the universal APK signed by the **Play app-signing key** from
Play Console after uploading the AAB. Alternatively, use an advanced signing
setup where the direct APK and Play-delivered APK are proven to share the exact
same app-signing certificate. Never publish the ordinary CI APK merely because
it is signed by the upload key.

Only after comparing the APK signer SHA-256 to the Play app-signing certificate
may a release manager publish this layout:

```text
download.webtui.vn/download/
  index.html
  styles.css
  app.js
  assets/android-chat-preview.png

download.webtui.vn/downloads/files/
  android/stable/app-prod-release.apk
  android/stable/app-prod-release.apk.sha256
  android/stable/mobile-release-manifest.json
```

The portal page and manifest are dormant until that certificate check passes.
Generate their checksum/metadata from the exported Play-signed APK, then test an
upgrade in both directions on a physical device before sharing the link.

## Local Signed Build

Create the upload keystore once if it does not exist yet:

```powershell
keytool -genkeypair -v -storetype PKCS12 -keystore android\app\upload-keystore.jks -alias upload -keyalg RSA -keysize 2048 -validity 10000
```

Create `android/key.properties` locally from the mobile project root:

```properties
storeFile=app/upload-keystore.jks
storePassword=...
keyAlias=...
keyPassword=...
```

Then run:

```sh
flutter pub get
flutter build appbundle --release --flavor prod -t lib/main_prod.dart --build-name=1.0.0 --build-number=100
flutter build apk --release --flavor prod -t lib/main_prod.dart --build-name=1.0.0 --build-number=100
```

On Flutter 3.44.x, the release build must not use `--no-pub` after running
tests or `flutter pub get`. Those commands can leave a dev-only plugin
registrant in the Android tree; the normal `flutter build` preparation step
must run so release plugin injection removes `integration_test` while retaining
all production plugins. The release workflow intentionally omits `--no-pub`.

## Play-first customer flow

Use a separately controlled local APK only for a QA group:

```powershell
cd C:\Users\MSI\Desktop\vpsttt-project\github-ready\webtui-chat-mobile
flutter pub get
dart run tool/check_architecture.dart
flutter analyze
flutter test
flutter build apk --release --flavor prod -t lib/main_prod.dart --build-name=1.0.0 --build-number=100
Get-FileHash build\app\outputs\flutter-apk\app-prod-release.apk -Algorithm SHA256
```

For customer distribution, upload the AAB to Play Internal/Closed testing. Do
not turn the locally built upload-key APK into a public fallback. If a fallback
is approved later, follow the certificate-safe procedure above.

Customer onboarding after install:

1. Owner installs or opens the self-hosted server first.
2. The first registered account becomes workspace owner.
3. Owner opens `/admin`, creates an invite token, and sends server domain plus token.
4. Customer installs APK, enters the server domain, chooses register, and pastes the invite token.

## Internal Install Checklist

- Install only APKs whose SHA-256 matches the artifact checksum.
- Keep release notes and manifest with the APK/AAB artifact.
- Use Play Internal testing for customer testers when possible.
- Use Firebase/direct APK only for controlled internal groups.
- Do not mix an upload-key APK install base with Play app-signing-key updates.
- Revoke and rotate upload keystore credentials immediately if a secret is exposed.

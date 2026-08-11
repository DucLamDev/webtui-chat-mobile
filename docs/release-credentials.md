# Mobile Release Credentials

Production secrets live in GitHub environment secrets or an equivalent managed
secret store. They must not be committed, copied into Dart source, or attached
to tickets and chat messages.

## Android Secrets

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`

Enable Play App Signing and treat this keystore as the upload key. Keep an
offline encrypted backup and document the key-reset recovery process. Grant the
release workflow access only through a protected production environment.

Create the upload key once on a trusted workstation. The command prompts for
passwords so they do not appear in shell history:

```powershell
keytool -genkeypair -v -keystore android/app/upload-keystore.jks `
  -keyalg RSA -keysize 4096 -validity 10000 -alias upload
keytool -exportcert -rfc -keystore android/app/upload-keystore.jks `
  -alias upload -file upload_certificate.pem
Copy-Item android/key.properties.example android/key.properties
```

`upload_certificate.pem` is ignored with the local keystore. Store it in the
same encrypted/offline release backup, not in git or a chat attachment.

If an old ignored `android/key.properties` exists but its referenced keystore is
missing, do not reuse or publish the plaintext values from that file. Replace it
only when the permanent keystore has been recovered or deliberately created and
backed up; rotate those credentials anywhere else they may have been used.

Replace the four placeholder values locally, register its public certificate as
the **upload** certificate in Play App Signing, and put the base64-encoded
keystore plus passwords in the protected release environment. Do not generate a
new key for routine releases. The Play app-signing certificate is a separate
identity in the recommended setup: use that certificate for OAuth/App Links and
never publish the CI upload-key APK as a customer fallback.

## Runtime Variables

- `MOBILE_REFERENCE_INSTANCE_URL` (preferred): publisher-operated, always-on
  reference/reviewer instance; customer servers are selected at runtime.
- `MOBILE_API_BASE_URL` (legacy fallback only): keep during migration, then remove
  after every protected environment defines `MOBILE_REFERENCE_INSTANCE_URL`.
- `MOBILE_APP_LINK_HOST`
- `MOBILE_PRIVACY_POLICY_URL`
- `MOBILE_TERMS_URL`
- `MOBILE_TERMS_VERSION`
- `MOBILE_PRIVACY_VERSION` (currently the same published policy version)
- `MOBILE_ACCOUNT_DELETION_URL`
- `MOBILE_SUPPORT_URL`
- `MOBILE_FIREBASE_API_KEY`: copy `client[].api_key[].current_key` from the
  downloaded Android `google-services.json`; this value is not visible in the
  supplied Firebase screenshots.
- `MOBILE_FIREBASE_MESSAGING_SENDER_ID=595077870179`
- `MOBILE_FIREBASE_PROJECT_ID=webtui-chat`
- `MOBILE_FIREBASE_ANDROID_APP_ID=1:595077870179:android:a6f4ff5cc14a0d1485be56`
- `MOBILE_FIREBASE_IOS_APP_ID` only when preparing the iOS release
- `PLAY_APP_SIGNING_SHA256_FINGERPRINTS` from Play App Signing, comma-separated
- `APPLE_TEAM_ID` only when the iOS association/release gate is enabled
- `ENABLE_IOS_RELEASE_CHECK=true` only when the Apple team/bundle configuration
  is provisioned and the same mobile tag must also run the unsigned iOS archive
  gate. Leave it unset while Google Play is the sole release target.

For a Google Play-only release, configure the portal with
`ENABLE_IOS_ASSOCIATION=false`, `APPLE_TEAM_ID=` and `APPLE_BUNDLE_ID=`. The AASA
route then returns a deliberate 404 and is not part of the Android gate. Before
shipping iOS, change the flag to `true`, fill the real Apple Team/Bundle IDs,
redeploy the portal, and require a direct 200 AASA response.

The official artifact is one universal AAB. Do not set either API variable to a
customer domain and do not create per-customer bundles. `MOBILE_APP_LINK_HOST`
is likewise the static publisher-controlled host declared by the manifest;
customer domains are entered manually after discovery. See
`docs/self-hosted-store-release.md` for the external release contract, signing
bootstrap and relay configuration.

Firebase client configuration is not a server credential, but it is still
managed centrally so dev/staging/prod projects cannot be mixed. Firebase service accounts,
APNs keys, App Store Connect API keys, and TURN secrets belong only on
the backend or release infrastructure and must never be passed through
`--dart-define`.

The three known Android identifiers are fixed directly in the release workflow.
Only `MOBILE_FIREBASE_API_KEY` must be added as a GitHub environment variable.
To print the exact five variable lines from the downloaded config without
guessing or opening it manually, run:

```powershell
.\scripts\read_firebase_android_config.ps1 -GoogleServicesJson C:\path\google-services.json
```

The Firebase Console Web Push certificate/VAPID public key is not an Android
FCM API key and must not be placed in `MOBILE_FIREBASE_API_KEY`.

The workflow validates presence, URL safety, identifier formats, signing, native
symbol stripping, merged permissions, and 16 KB alignment before publishing a
release artifact.

For the first Play upload only, follow the documented bootstrap sequence: upload
a signed Internal-only AAB, obtain the Play App Signing SHA-256, redeploy
`assetlinks.json`, set `PLAY_APP_SIGNING_SHA256_FINGERPRINTS`, then build a new
versionCode through the complete gate. Never use the upload certificate in the
production association file.

If Play Console already shows the real App signing key certificate before the
first upload, skip the bootstrap job and configure that fingerprint directly.

The exact one-time workflow procedure is:

1. In repository **Settings > Environments > production**, configure all four
   Android secrets above and all runtime variables except the not-yet-issued
   `PLAY_APP_SIGNING_SHA256_FINGERPRINTS`. Use the same permanent upload key that
   was registered in Play; never create a temporary bootstrap keystore.
2. Open **Actions > Mobile CI and release > Run workflow**. Set
   `bootstrap_version` to a three-part SemVer such as `1.0.0`, and enter exactly
   `INTERNAL_ONLY_DO_NOT_PROMOTE` in `confirm_play_signing_bootstrap`.
3. Approve the protected `production` environment if required. The
   `android-play-signing-bootstrap` job signs and verifies the AAB but deliberately
   skips only the unavailable fingerprint/public-association probe. It never
   uploads to Play automatically.
4. Download `android-play-signing-bootstrap-INTERNAL-ONLY-...` before its 7-day
   retention expires. Verify the `.sha256`, then manually upload the clearly
   named `app-prod-play-signing-bootstrap-INTERNAL-ONLY.aab` only to Play Internal
   testing. Never promote this release.
5. Copy the **App signing key certificate** SHA-256 from Play Console, set
   `PLAY_APP_SIGNING_SHA256_FINGERPRINTS`, publish it in `assetlinks.json`, and
   verify the public endpoint. Create a `mobile-vX.Y.Z` tag only after that; the
   normal `android-release` job creates the new versionCode and releasable AAB.

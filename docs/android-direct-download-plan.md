# Android Direct Download Plan

This plan defines the only safe fallback after Google Play App Signing is
configured. It is scoped to signed Android APK delivery only and deliberately
does not publish the CI upload-key APK.

## Goal

- Use Play Internal/Closed testing as the primary delivery channel.
- If an approved public fallback is needed, give users one trusted URL:
  `https://download.webtui.vn/download/`.
- Publish only a universal APK exported from Play Console, or another APK whose
  signer is proven identical to the Play app-signing certificate.
- Show version, channel, release notes, and SHA-256 checksum on the download
  page.
- Never publish the ordinary upload-key APK produced by CI.

## Implemented Static Page

The static download page lives in `portal/download/` in the monorepo:

- `index.html`: Android-first download page.
- `styles.css`: responsive visual design.
- `app.js`: reads release metadata from manifest JSON.
- `assets/android-chat-preview.png`: current mobile chat preview screenshot.
- `privacy.html`: minimal privacy/support page for the internal Android channel.
- `mobile-release-manifest.example.json`: example metadata contract.

The page attempts to read manifests in this order:

1. `android/stable/mobile-release-manifest.json`
2. `mobile-release-manifest.json`
3. `mobile-release-manifest.example.json`

## Visual Direction

- First viewport is the actual Android download action, not a marketing hero.
- Use the current mobile chat screenshot as the main product preview.
- Keep one primary action: download signed Android APK.
- Show Google Play only when `store_url` is present in the manifest.
- Surface checksum, version, channel, and release notes near the action.
- Use warning copy for sideload trust: install only from
  `download.webtui.vn/download/`, Firebase App Distribution, or Google Play links
  controlled by the team.

## Publish Flow

1. Upload the CI-signed `app-prod-release.aab` to Play Internal/Closed testing.
2. In Play Console, export a universal APK signed with the Play app-signing key.
3. Verify its signing-certificate SHA-256 exactly matches the certificate shown
   under App integrity. Abort on any mismatch.
4. Generate a fresh SHA-256 checksum and release manifest from that exported
   APK; do not reuse the CI upload-key APK checksum.
5. Upload the verified APK and checksum to:
   `download.webtui.vn/downloads/files/android/stable/`.
6. Upload the manifest as:
   `download.webtui.vn/download/android/stable/mobile-release-manifest.json`.
7. Keep the same manifest fields in the backend
   `/mobile/releases/{platform}/{channel}/{current_version}` response.
8. On physical devices, prove direct-to-Play and Play-to-direct updates preserve
   app data and install without a signature error before sharing the link.

## Security Rules

- Do not upload `.jks`, `.keystore`, `key.properties`, Firebase service account
  JSON, tester email lists, or CI secrets to the download host.
- Do not publish debug APKs.
- Do not publish an APK signed only with the Play upload key.
- Require the published APK signer to match the Play app-signing SHA-256.
- Do not publish an APK if its SHA-256 does not match the generated checksum.
- Do not replace a published version in place; publish a new versionCode and
  manifest update instead.
- Use HTTPS only.

## Google Play Later

Add `store_url` to the manifest and make CH Play the primary action. Keep a
direct APK action only when the signature-safe publish flow above is continuously
enforced for every release.

# Mobile Store Release Readiness

Audit date: 2026-08-07. Re-check store policies before every submission because
target SDK, privacy, and permission rules change over time.

## Current Verdict

The source is suitable for a signed Android production-candidate build and
unsigned iOS CI validation. Source-side UGC, legal acceptance, public-policy,
app-association, permission, signing, and native-alignment blockers are now
implemented. It is **not yet possible to upload or publish from this checkout**
because several owner-controlled items cannot be completed in source control:

- production signing/provisioning and store accounts;
- deployment of the public privacy/account-deletion pages plus final legal
  entity, support, retention, and data-controller review;
- production Firebase, APNs, and VoIP push credentials plus end-to-end device
  testing;
- Play Console permission declarations and App Store privacy answers;
- production deployment and end-to-end verification of legal acceptance,
  report/block/moderation, and account deletion;
- signed iOS archive/TestFlight validation on macOS.

Do not create placeholder credentials or submit declarations that do not match
the production backend.

## Source Gates Already Enforced

- Android production ID: `com.vpsttt.webtui_chat`; iOS bundle ID currently:
  `com.vpsttt.webtuiChat`. Confirm both are the intended permanent IDs before
  the first store record is created.
- Android targets API 36 and has `minSdk 24` with the audited Flutter toolchain.
- Release CI derives a monotonically increasing build number from
  `GITHUB_RUN_NUMBER`; a `mobile-vX.Y.Z` tag supplies the public version.
- Android release signing is read only from protected CI secrets or an ignored
  local `key.properties`; debug signing is not used for release artifacts.
  Release tasks fail closed when signing is incomplete. Maintainers may set the
  Gradle property `WEBTUI_ALLOW_UNSIGNED_RELEASE=true` only for local compile
  validation; the resulting artifact must never be uploaded or distributed.
- `sqlite3_flutter_libs` (EOL) was replaced by `sqlite3` Native Assets and Drift
  was upgraded. Android CI checks APK 16 KB ZIP alignment.
- Android disables cleartext production traffic and app-data backup. Debug
  builds alone allow cleartext for local development.
- Broad storage/photo/audio permissions contributed by `open_filex` are removed
  from the merged manifest. Attachments use system pickers and app-owned files.
- `flutter_background`, screen sharing, and the `mediaProjection` foreground
  service are removed from the first Play release. Reintroducing screen share
  requires a native consent-first implementation and a new Play declaration.
- The call plugin's custom permission is upgraded from `normal` to `signature`.
- Main app content no longer forces itself over the lock screen; the dedicated
  incoming-call surface handles that use case.
- Android creates a high-importance `webtui_messages` notification channel and
  supplies a monochrome notification icon.
- iOS has production/development APS entitlements, PushKit handling, background
  audio/VoIP modes, Face ID/local-network/camera/microphone/photo descriptions,
  an app-level privacy manifest, and a committed CocoaPods `Podfile`. The
  manifest is a source baseline; reconcile it with Xcode's aggregated privacy
  report and the final App Store Connect answers for every release.
- The in-app privacy screen exposes a privacy-policy link when the release URL
  is configured and includes typed confirmation for permanent account deletion.
- Registration loads the current legal-document versions from the backend,
  requires explicit Terms/Privacy acceptance, links both public documents, and
  sends the accepted versions for immutable server-side audit records.
- Users can report a message or workspace user, block/unblock abusive users,
  and manage blocked accounts. Backend enforcement prevents direct messages,
  direct-channel creation, and calls across either direction of a block; the
  moderation queue is permission-gated and audited.
- Android App Links and iOS Universal Links are backed by public association
  files. Release CI verifies the exact Play App Signing fingerprints and Apple
  team/bundle application identifier before building.
- Logout and account deletion remove cached per-server refresh tokens, local
  workspace/session cache, and app-lock credentials.

Run:

```sh
dart format --set-exit-if-changed lib test integration_test tool
dart run tool/check_architecture.dart
dart run tool/check_mobile_release.dart
flutter analyze
flutter test
flutter build apk --debug --flavor dev -t lib/main_dev.dart
```

## Production Push Model For A Store Binary

FCM and APNs credentials belong to the app IDs and must never ship in the app or
be published to arbitrary self-hosted instances. A single store binary therefore
needs one of these models:

1. **Recommended: minimal push relay.** The publisher operates a small relay
   holding Firebase service-account and APNs keys. Each self-hosted instance is
   registered with its own revocable signing credential. It sends only opaque
   event IDs, workspace/server routing IDs, call state, and optionally a generic
   notification label. The phone fetches message content directly from its
   selected self-hosted server after wake/open. Apply per-instance rate limits,
   replay protection, audit logs, and immediate token deletion.
2. **Fully independent build.** A self-hoster changes both app IDs, supplies its
   own Firebase/APNs/Apple team, and distributes its own signed app. This is not
   the same binary published by VPSTTT.

WebSocket or polling alone cannot provide reliable background delivery on iOS
and modern Android. Never place message bodies, access tokens, self-host admin
credentials, or arbitrary URLs in push payloads. Notification navigation must
remain allow-listed by `NotificationTarget`.

Release CI requires these GitHub repository variables:

- `MOBILE_FIREBASE_API_KEY` from Android `google-services.json`
- Sender ID is fixed in CI to `595077870179`
- Firebase project is fixed in CI to `webtui-chat`
- Android App ID is fixed in CI to
  `1:595077870179:android:a6f4ff5cc14a0d1485be56`
- `MOBILE_FIREBASE_IOS_APP_ID` only when preparing the iOS release
- `MOBILE_APP_LINK_HOST`
- `MOBILE_PRIVACY_POLICY_URL` (public HTTPS URL)
- `MOBILE_TERMS_URL`
- `MOBILE_TERMS_VERSION`
- `MOBILE_PRIVACY_VERSION`
- `MOBILE_ACCOUNT_DELETION_URL`
- `MOBILE_SUPPORT_URL`
- `MOBILE_API_BASE_URL`
- `PLAY_APP_SIGNING_SHA256_FINGERPRINTS`
- `APPLE_TEAM_ID` only when `ENABLE_IOS_RELEASE_CHECK=true`; for a Play-only
  release, keep the portal `ENABLE_IOS_ASSOCIATION=false` and both Apple identity
  values empty so the AASA route fails closed with HTTP 404.

Google OAuth is fail-closed and hidden in the production flavor. Do not pass
OAuth client IDs to a store build until the new-user flow has an explicit,
tested legal-consent step. Existing organization OIDC identities may sign in,
but backend JIT creation remains disabled until the user has registered and
accepted the current documents through a supported flow.

The backend/relay additionally needs a Firebase service account and APNs token
key (`.p8`, Key ID, Team ID, bundle/topic mapping). Those are server secrets,
not GitHub variables passed to Flutter builds.

## Implemented Account Deletion: Deployment And Policy Verification

The source now includes the authenticated mobile deletion flow,
`DELETE /api/v1/users/me`, and the unauthenticated public deletion-request page.
Before store review, deploy them to the final production domains and verify:

- the endpoint accepts authenticated body `{ "confirmation": "DELETE",
  "ownership_successor_email": "member@example.com" }` (successor optional
  unless the account owns a workspace), transfers ownership atomically, and
  revokes refresh/access sessions, push devices, API tokens, and OAuth grants;
- documented behavior for authored messages/files, audit/legal retention, and
  deletion completion time;
- the public HTTPS deletion page remains reachable without authentication and
  is entered in Play Console in addition to the in-app path;
- idempotent behavior so a retried deletion does not restore or duplicate data;
- `POST/PUT /api/v1/mobile/devices` and deletion endpoints that reject tokens
  belonging to another user/workspace and expire stale FCM/APNs tokens.

## Google Play Console Checklist

- [ ] Verify the Play developer identity and create the permanent app record.
- [ ] Enable Play App Signing; back up the upload key and restrict CI secrets to
      a protected release environment.
- [ ] Upload the signed AAB, not the APK, and confirm version code increments.
- [ ] Confirm API 36 and 16 KB page-size compatibility in App Bundle Explorer
      for every native library, including WebRTC and SQLite.
- [ ] Complete Data safety for account/profile data, user messages/files/audio,
      workspace membership, device ID, FCM/APNs tokens, sessions, and any
      diagnostics actually enabled in production.
- [ ] Supply the privacy-policy URL and account-deletion web URL.
- [ ] Complete foreground-service declarations for `phoneCall`, `microphone`,
      and `camera`, including reviewer videos of incoming and outgoing
      audio/video calls, runtime-permission allow/deny paths, backgrounding,
      and hang-up cleanup.
- [ ] Complete the full-screen-intent declaration. Calling must be a genuine
      core feature and the app must degrade to a normal notification if access
      is denied.
- [ ] Confirm the final merged manifest does not contain `READ_MEDIA_*`,
      `READ_EXTERNAL_STORAGE`, or `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`.
- [ ] Host a valid `/.well-known/assetlinks.json` on the configured app-link
      host with the production package and Play signing certificate digest.
- [ ] Provide the two valid phone screenshots and feature graphic, plus
      short/full descriptions, support email, category, content rating, ads
      declaration, and reviewer credentials for a non-production demo
      workspace. If the tablet/Chromebook section is populated, first capture
      at least four real 1080-7680 px screenshots at 9:16 or 16:9.
- [ ] Run Internal -> Closed testing, Play pre-launch report, accessibility
      checks, Android 14/15/16 calls, background push, process-death recovery,
      and offline outbox. Launch the first Production release with deliberate
      country/region scope and a named halt/unpublish owner; percentage staged
      rollout applies only to later updates.
- [ ] Verify a reporter can report message/user, block/unblock, and that a
      moderator can action the queue and remove offending content using the
      reviewer account without requiring private operator assistance.

## App Store Connect Checklist

- [ ] Enroll the legal entity, register the permanent bundle ID, enable Push
      Notifications and Background Modes, and create Distribution certificate,
      App Store provisioning profile, and App Store Connect API key.
- [ ] On macOS, run `pod install`, review and commit `Podfile.lock`, then build a
      signed archive using the Release entitlement. The current CI job validates
      an unsigned build only; it does not produce an uploadable IPA.
- [ ] Verify the archive's effective `aps-environment=production`, bundle ID,
      version/build number, icons, embedded provisioning profile, SDK privacy
      manifests/signatures, and export-compliance answer.
- [ ] Generate Xcode's privacy report. Complete App Privacy for names,
      email/phone/user IDs, messages/files/photos/audio, workspace/account data,
      device/push identifiers, and diagnostics actually collected. Mark data as
      linked to the user where applicable; do not claim tracking unless it
      occurs.
- [ ] Publish the final privacy policy and support URL in metadata and keep the
      in-app link functional without requiring a new release.
- [ ] Confirm account deletion removes the full account rather than only
      deactivating it, and document any legally retained data.
- [ ] Add and verify a server-side method that filters objectionable material
      before it is posted. Report/block tooling and later human review alone do
      not satisfy Apple Guideline 1.2's separate filtering requirement.
- [ ] Configure and test FCM APNs plus the separate APNs VoIP topic on physical
      devices in foreground, background, terminated, token rotation, decline,
      timeout, and call-ended scenarios. Every VoIP push must promptly report a
      real incoming call to CallKit.
- [ ] Supply iPhone/iPad screenshots, age rating, category, review notes,
      reviewer demo account/server, copyright, privacy/support URLs, and staged
      TestFlight testing.
- [ ] Before an iOS release, enable the portal association and verify Associated
      Domains contains `applinks:chat.vpsttt.com`, the AASA
      response is HTTP 200 without redirect, and both cold/warm universal links
      open only allow-listed in-app routes.

## Remaining Quality Work

- Capture final screenshots from the signed production candidate on the exact
  phone/tablet locales selected in each store, then compare them with the
  deterministic listing assets before upload.
- Replace the legacy blank iOS `LaunchImage` with an approved full-bleed brand
  asset during the signed Xcode archive pass; Android already uses adaptive,
  monochrome and Android 12 light/dark launch resources.
- Add native iOS dev/staging schemes if QA needs multiple variants installed at
  once. The production store target already uses `main_prod.dart`.
- Add a signed iOS archive/upload workflow only after certificates and protected
  App Store Connect secrets are provisioned.

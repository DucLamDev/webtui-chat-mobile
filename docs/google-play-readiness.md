# Google Play Readiness

Use this document for Google Play and Android distribution readiness. Source
audit date: 2026-08-07. Re-check the linked policies before every submission.

## Current Source Status

The repository now contains the source-side release blockers required for a
production candidate: API 36 targeting, fail-closed release signing, 16 KB ZIP
and ELF alignment checks, public-policy and app-link probes, legal acceptance,
account deletion, UGC report/block flows, moderation enforcement, Data Safety
source-of-truth answers, reviewer instructions, and deterministic store assets.

An actual production upload remains intentionally blocked until the publisher
provides the Play developer account, Play App Signing/upload key, production
Firebase configuration, final legal identity/retention decisions, a deployed
backend/portal, and a working reviewer account. Never replace those items with
placeholder values just to make CI green.

## Package And Track

- Production `applicationId`: `com.vpsttt.webtui_chat`.
- App name: `WebTUI Chat`.
- Default language: Vietnamese.
- App category: Communication or Business, depending on final Play Console positioning.
- Distribution plan: Play Internal testing -> Closed testing -> first Production
  release, scoped by countries/regions when needed. The first Production release
  cannot use percentage staged rollout; use staged rollout for later updates.
- Play App Signing: enabled before the first production upload.

## Target API

Google Play target API policy is date-sensitive:

- The production build targets Android 16/API 36 and fails closed if a release
  resolves to a lower target.
- Target-level policy and compatibility deadlines are date-sensitive. Verify
  them at the official links below immediately before uploading.

Before every release, verify the current policy at:

- https://developer.android.com/google/play/requirements/target-sdk
- https://support.google.com/googleplay/android-developer/answer/11926878

The same pre-submission review must re-check the official UGC and account
deletion requirements rather than relying only on this repository snapshot:

- https://support.google.com/googleplay/android-developer/answer/9876937
- https://support.google.com/googleplay/android-developer/answer/12923286
- https://support.google.com/googleplay/android-developer/answer/13327111

## Store Listing

- Short description: secure workspace chat for teams.
- Full description: explain workspace chat, channels, direct messages, files, notifications, bot/automation admin surfaces, and privacy controls.
- Screenshots: the two current Vietnamese phone captures satisfy the minimum
  listing publication count and contain no real personal data. Before
  populating tablet/Chromebook sections, capture at least four real screens
  from the signed AAB at 1080-7680 px and 9:16 or 16:9; do not upload the
  retired 1024x768 tablet reference.
- Feature graphic: required before production.
- Privacy policy URL: required before wider distribution.
- Support email: required.

## Data Safety

Data safety declaration must match actual app behavior:

- Account info: email/username/profile if used.
- User content: messages, files, attachments, reactions.
- App activity: notification/device registration, session/device state, diagnostics if enabled.
- Device or other IDs: app-generated device ID, FCM token when push is enabled.
- Security practices: HTTPS transport, secure storage for refresh token, access token memory-only, workspace-scoped cache.
- Data deletion: authenticated `DELETE /api/v1/users/me` plus the public
  account-deletion page. Verify both against the deployed production backend.
- User safety: moderation reports, user blocking, operator queue/audit, and
  blocked direct-interaction enforcement. Verify the end-to-end workflow with
  the exact reviewer account.

## Permission Declaration

Current Android manifest uses:

- `INTERNET`/network state: backend API, WebSocket, WebRTC, file transfer, push.
- `CAMERA`: avatar/chat capture and user-started video calls.
- `RECORD_AUDIO`/audio routing/Bluetooth: voice messages and calls.
- `POST_NOTIFICATIONS`: Android 13+ push notification permission.
- `FOREGROUND_SERVICE_PHONE_CALL`, `FOREGROUND_SERVICE_MICROPHONE`,
  `FOREGROUND_SERVICE_CAMERA`, `MANAGE_OWN_CALLS`, and
  `USE_FULL_SCREEN_INTENT`: user-visible incoming audio/video calls supplied by
  the call plugin.

Screen sharing is disabled in the first Play release. The production manifest
therefore contains no `mediaProjection` service or permission. Accepted calls
start as `phoneCall` only and add microphone/camera service types only after the
visible runtime-permission flow succeeds.

The app deliberately removes plugin-contributed `READ_MEDIA_*`,
`READ_EXTERNAL_STORAGE`, and `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` permissions.
Camera, front camera, microphone, and Bluetooth are declared as optional
hardware features so Play does not filter text-chat-capable tablets,
Chromebooks, or other devices that cannot place every kind of call.
Complete the Play Console foreground-service and full-screen-intent declarations
with reviewer videos before production.

The merged production manifest is checked in CI. CI also rejects broad
storage/media/location/contact/SMS/install/overlay permissions and exported
components without an explicit protection model.

See `store-release-readiness.md` for the cross-store blocking checklist.

## Test Tracks

Internal testing checklist:

- Upload signed AAB from M11 workflow.
- Confirm the AAB is signed by the upload key and Play App Signing is enabled.
- Confirm versionCode increments.
- Add internal testers.
- Run pre-launch report.
- Confirm deep links and notification open targets.
- Verify app installs and signs in on at least the M10/M11 device matrix.

Closed/open testing checklist:

- For a personal developer account created after 13 November 2023, keep at
  least 12 testers continuously opted in to the closed test for 14 days before
  applying for production access; re-check this date-sensitive rule in Play
  Console: https://support.google.com/googleplay/android-developer/answer/14151465
- Use real workspace test data.
- Verify support/privacy links.
- Verify Terms acceptance, report message/user, block/unblock, moderation
  resolution, and account deletion with the disposable deletion-test account.
- Monitor crash/ANR and notification delivery.
- For the first Production release, assign a halt/unpublish owner and control
  scope with testing plus countries/regions. For later updates, keep a staged
  rollout pause/halt owner assigned.

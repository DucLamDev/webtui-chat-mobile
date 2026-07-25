# Google Play Readiness

Use this document for Phase M12 Google Play and Android distribution readiness.

## Package And Track

- Production `applicationId`: `com.vpsttt.webtui_chat`.
- App name: `Webtui Chat`.
- Default language: Vietnamese.
- App category: Communication or Business, depending on final Play Console positioning.
- Distribution plan: Play Internal testing -> Closed testing -> Production staged rollout.
- Play App Signing: enabled before the first production upload.

## Target API

Google Play target API policy is date-sensitive:

- Current 2025 requirement: new apps and updates target Android 15/API 35 or higher.
- Starting August 31, 2026: new apps and updates target Android 16/API 36 or higher; existing apps must target Android 15/API 35 or higher for discoverability on newer Android versions.

Before every release, verify the current policy at:

- https://developer.android.com/google/play/requirements/target-sdk
- https://support.google.com/googleplay/android-developer/answer/11926878

## Store Listing

- Short description: secure workspace chat for teams.
- Full description: explain workspace chat, channels, direct messages, files, notifications, bot/automation admin surfaces, and privacy controls.
- Screenshots: phone and tablet, Vietnamese UI, no fake personal data.
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
- Data deletion/export: backend endpoint is still a required backlog item before broad public release.

## Permission Declaration

Current Android manifest uses:

- `INTERNET`: backend API, WebSocket, file transfer, push.
- `CAMERA`: avatar and chat image capture.
- `POST_NOTIFICATIONS`: Android 13+ push notification permission.

Do not declare microphone/background/call permissions until voice/video call UX is fully wired and policy rationale is ready.

## Test Tracks

Internal testing checklist:

- Upload signed AAB from M11 workflow.
- Confirm versionCode increments.
- Add internal testers.
- Run pre-launch report.
- Confirm deep links and notification open targets.
- Verify app installs and signs in on at least the M10/M11 device matrix.

Closed/open testing checklist:

- Use real workspace test data.
- Verify support/privacy links.
- Monitor crash/ANR and notification delivery.
- Keep staged rollout pause/halt owner assigned.

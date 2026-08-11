# Foreground Service And Full-Screen Intent Evidence

The merged production manifest is the authority. Run
`dart run tool/check_android_manifest.dart <merged-manifest>` after every
release build.

## Phone Call

- Type: `phoneCall`.
- User-visible feature: receive and maintain an explicitly initiated WebTUI
  audio/video call while the application is backgrounded.
- If deferred/interrupted: ringing or the active call can be missed or dropped.
- Evidence video: launch app, sign in, receive a call, accept it, background the
  app, return, and end the call. Also show the normal-notification fallback when
  full-screen intent access is denied.

## Microphone And Camera

- Types: `microphone`, `camera`.
- User-visible feature: capture media during a call only after the user joins
  and grants the corresponding runtime permission.
- If deferred/interrupted: the participant continues in listen-only or
  camera-off mode; text chat remains usable.
- Evidence video: show the in-app explanation, both allow and deny paths, mute,
  camera-off defaults, system indicators, and stopping capture on hang-up.

The accepted-call service starts as `phoneCall` only. It is promoted to
`microphone` and, for video calls, `camera` only after the call screen's visible
runtime permission flow succeeds and native code verifies the grants. Denial or
an invalid/background promotion fails closed and the call is terminated.

## Full-Screen Intent

Declare that the app's core communication function includes incoming audio and
video calls. The binary must check access and degrade to a high-priority normal
notification when automatic full-screen access is unavailable. Never use the
intent for ordinary chat messages, marketing, reminders, or background sync.

Store the final unlisted video URLs in Play Console or the release's private
operations record. Do not commit reviewer-only video URLs or credentials.

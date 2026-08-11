# WebTUI Android foreground-service patch

This directory vendors `flutter_callkit_incoming` 3.1.3.

The upstream Android notification service starts accepted and outgoing calls
with `phoneCall|microphone|camera` immediately. On Android 14+ that can throw
before the visible runtime permission flow has granted microphone/camera.

The WebTUI patch makes the first foreground start `phoneCall`-only, verifies
app visibility plus `RECORD_AUDIO`/`CAMERA` grants natively, and only then
promotes the same notification service to the media types. The
`activateCallMedia` channel method handles accepted incoming calls. Outgoing
`startCall` is rejected fail-closed if those conditions are not met.

When updating upstream, port and re-run the source/manifest tests covering
`CallkitNotificationService`, `activateCallMedia`, and the local path pin.

The fork also contains process-recreation safety that must be preserved:

- `CallkitNotificationManagerProvider` gives the receiver and foreground
  service a process-owned manager before Flutter attaches. Once that fallback
  is created it remains authoritative, so attaching an engine cannot switch
  sound-player instances and strand a ringtone.
- `CallkitPendingActionStore` synchronously persists accept, decline, end, and
  timeout before best-effort EventChannel delivery. For terminal actions, the
  receiver holds a strictly bounded `goAsync` lease for the prompt attempt and
  enqueues a unique network-constrained `CallkitPendingActionWorker`;
  WorkManager owns process lifetime and persistent retry after that lease. The
  worker marshals engine startup onto the Android main thread and lazily starts
  `CallkitBackgroundExecutor` from the persisted
  callback handle, and a readiness handshake buffers the first event until Dart
  is listening (the native channel is installed before Dart starts). The
  minimal Dart handler exact-matches secure HTTPS
  server/workspace bindings, refreshes secure auth when needed, performs the
  terminal API action with redirects disabled, and acknowledges only after API
  success or a fresh read proves the call terminal/not found. Failed actions
  remain available through `getPendingCallActions` for bounded retry and app
  replay. The auxiliary engine is lazy and has a bounded idle lifetime. Accept
  is intentionally excluded from headless API mutation/ack: notification and
  Telecom accept foreground the app, and visible WebRTC media setup accepts the
  server call only after permission succeeds.
- `CallkitConnection` routes Telecom/system UI, Bluetooth, and watch
  `onAnswer`/`onReject`/`onDisconnect`/`onAbort` callbacks through the same
  receiver and durable queue. `EXTRA_ACTION_FROM_TELECOM` prevents feedback
  into the originating Android `Connection`.

When updating upstream, also port and re-run the durable-action source/Dart
tests and the physical cold-process accept/decline/timeout matrix.

# Android API 34–36 call foreground-service validation

Run this matrix on physical Android 14, 15, and 16/API 36 devices before the
first Play production rollout. Use a production-flavor internal-testing build,
a real FCM project, and two non-reviewer test accounts. Record the device model,
OS build, app version code, result, and an unlisted evidence-video URL.

## Static pre-check

1. Confirm `flutter_background` is absent from `flutter pub deps`.
2. Inspect the merged production manifest and confirm there is no
   `mediaProjection` type or `FOREGROUND_SERVICE_MEDIA_PROJECTION` permission.
3. Confirm the CallKit notification service declares
   `phoneCall|microphone|camera` and the matching foreground-service
   permissions.
4. Run `dart run tool/check_android_manifest.dart <merged-manifest.xml>`.

## Incoming calls

For both audio and video, test with the app foregrounded, backgrounded, and the
device locked:

1. Fresh-install the build and leave camera/microphone ungranted.
2. Receive and accept the call. Verify the initial ongoing notification appears
   without a `ForegroundServiceStartNotAllowedException` or
   `SecurityException`; this first service start is `phoneCall` only.
3. Verify the app presents the Android runtime permission UI from the visible
   call screen. Before approval, verify there is no microphone/camera privacy
   indicator.
4. Grant microphone (and camera for video). Verify media connects and the same
   service is promoted to the matching media type(s).
5. Repeat with each permission denied. The call must fail closed, stop capture,
   remove its ongoing notification/service, and leave text chat usable.

### Cold-process accept

Repeat audio and video acceptance after the incoming notification is visible
but the Flutter engine is no longer attached. On a test device where the
incoming notification remains posted, use `adb shell am kill
com.vpsttt.webtui_chat`, confirm the old PID is gone, then tap Accept from the
notification/lock screen. Confirm a new process starts, the ongoing-call
notification is posted immediately, and the call activity opens. There must be
no `RemoteServiceException`, "did not then call Service.startForeground",
5-second foreground-service timeout, crash, or ANR. This case verifies that the
native process-owned notification manager works before plugin registration.
Repeat the same process-recreated setup for Decline and Timeout. Decline must
remove the ringing notification, while Timeout must replace it with the missed
call notification; neither path may depend on a Flutter engine being attached.
After network/authentication becomes available, verify each persisted action is
replayed exactly once to the API and disappears from the native pending queue.
Force offline mode before tapping Decline, relaunch once while still offline,
then restore connectivity: the server call must leave `ringing` and a second
relaunch must not submit another mutation.
Also repeat Decline with the UI process killed but a valid secure session: the
bounded receiver lease must make the first attempt without opening the app; if
it cannot complete, the pending-action WorkManager job must own the process and
retry after the receiver returns, completing the reject API before the natural
server timeout, acknowledge the queue entry, and stop its auxiliary Flutter
engine. Capture WorkManager state and logs for the `initialized` handshake. Repeat
once with an expired access token and valid refresh token. A redirect response,
server-origin mismatch, workspace mismatch, or unavailable credentials must
never receive an Authorization header and must leave the action queued.

### Telecom and companion-device actions

For an incoming call registered with Android Telecom, accept and reject from
the system call UI, a paired Bluetooth headset, and a paired watch where
available. End an accepted call from each surface. Repeat accept/reject once
after killing the Flutter process while leaving the OS call surface alive.
Confirm WebRTC/API state matches the native state, the action is replayed after
auth is ready, and no receiver-to-Connection feedback loop produces duplicate
notifications or terminal events.

## Outgoing and terminal lifecycle

1. Start audio and video calls with permissions ungranted. Confirm the native
   outgoing lifecycle and ongoing FGS begin only after the visible grant flow.
2. Background and restore an active call; verify media and the ongoing
   notification remain stable.
3. End from each side, reject, time out, force a WebRTC setup failure, press
   Back, and swipe the activity away. Every terminal path must stop capture and
   the ongoing CallKit notification/service.
4. Repeat with notification permission and full-screen-intent access denied;
   incoming calls must use the documented notification fallback.

During every case, capture filtered `adb logcat` for
`ForegroundServiceStartNotAllowedException`, `SecurityException`,
`MissingForegroundServiceTypeException`, and `flutter_callkit_incoming`. Use
`adb shell dumpsys activity services com.vpsttt.webtui_chat` immediately before
and after media permission approval and after hang-up to verify the transition
and teardown.

Physical-device execution is a release-owner gate; automated source, Dart, and
merged-manifest checks complement it but do not replace it.

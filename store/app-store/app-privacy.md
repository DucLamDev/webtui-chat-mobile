# App Store Privacy And Review Source Of Truth

Reconcile these answers with the released iOS archive and deployed services.

## Collected Data

- Contact info: name, email, optional phone number.
- Identifiers: account/user ID and an app-generated device ID.
- User content: messages, files, photos/videos, audio, and collaboration data.
- Usage data: workspace/session, notification, synchronization, moderation, and
  security-audit events required to operate the service.
- Diagnostics: not collected by the current source; update before enabling a
  diagnostics or crash-upload SDK.

Purposes are App Functionality, Account Management, and Security. The current
source does not track users across companies' apps or websites, access the IDFA,
sell data, or include advertising.

## Embedded VPSTTT IDE (Draft, Waiting For The IDE Operator)

The binary can open the company's VPSTTT IDE in a WebView. The entry appears
only on the company's internal server after its administrator enables it; every
other server never shows it.

- Sign-in: the IDE password, 2FA code, and PIN are entered on the IDE's own
  website in the system browser. They do not pass through the app or the chat
  server.
- Sent when the user opens it: name and email (by the chat server), platform,
  app version, and up to two device-key identifiers.
- Sent while using it: what the user types, uploads, or says to the embedded
  page. Audio needs an in-app confirmation and the system permission, shows a
  recording indicator, and stops when the user leaves the screen, locks the
  app, sends it to the background, or is in a call.
- Processing stated by the IDE operator: voice clips go to the company's
  speech-recognition service (AI-API for VPSTTT) to produce text, and the IDE
  gateway does not write raw audio to disk. Text the user asks to hear is sent
  to a text-to-speech service. The IDE keeps its chat history, task prompts,
  attached files, and result files; result downloads are limited to the task
  owner or an authorized operator.
- Device keys: private keys stay in the Secure Enclave. Only public keys and
  signatures over challenges issued by the IDE are sent.
- Purposes: App Functionality and Security. No tracking, no advertising.
- Still to be confirmed by the IDE operator before submission: retention
  periods for chat history, prompts, and files; whether AI-API for VPSTTT
  passes audio or text to outside AI providers (and which); how users request
  deletion.

Guidelines 4.7 and 4.7.2: the embedded page can call only a small, fixed set of
app functions, and the app asks the user before creating or deleting a device
key or saving a file. State this in the review notes, and give the reviewer an
account on a server where the feature is enabled or state that it is off there.
If Apple objects, the server administrator can turn these functions off for iOS
without an app update; the IDE then asks for the password and 2FA code on every
open and serves result files through the system browser. A reviewer account
needs an IDE test account with 2FA from the IDE operator (not issued yet).

## Review Requirements

Do not submit the current iOS build yet. The backend has reporting, blocking,
evidence retention, operator response tooling, and content removal, but it does
not yet filter objectionable material before publication. Apple Guideline 1.2
lists filtering as a separate UGC requirement; implement and test that control
before TestFlight is promoted to App Review.

- Supply a reusable demo server/account without OTP.
- Explain that organization-selected self-hosted servers control workspace
  content and retention.
- Show in-app account deletion and the public deletion URL.
- Demonstrate report message/user and block user for user-generated content.
- Explain background modes (`audio`, `voip`, `remote-notification`) and provide
  working incoming-call test data if calls are included in the review build.

The final archive must include the aggregated privacy manifests from all SDKs.
Generate and inspect Xcode's privacy report before upload.

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

- Sent when the user opens it: name and email (by the chat server), platform,
  app version, and up to two device-key identifiers.
- Sent while using it: what the user types, uploads, or says to the embedded
  page. Audio needs an in-app confirmation and the system permission, shows a
  recording indicator, and stops when the user leaves the screen, locks the
  app, sends it to the background, or is in a call.
- Device keys: private keys stay in the Secure Enclave. Only public keys and
  signatures over challenges issued by the IDE are sent.
- Purposes: App Functionality and Security. No tracking, no advertising.
- Must be confirmed by the IDE operator before submission: retention of audio,
  prompts, and files; AI sub-processors; deletion on request.

Guidelines 4.7 and 4.7.2: the embedded page can call only seven app functions
(app info; device-key status, create, sign, delete; save a file; close). State
this in the review notes, and give the reviewer an account on a server where
the feature is enabled or state that it is off there. If Apple objects, the
server setting `IDE_WEB_BRIDGE_PLATFORMS` turns these functions off for iOS
without an app update.

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

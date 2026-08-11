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

# Privacy Policy Draft

This is an operational draft for Play Console readiness. Legal review is required before public production release.

## Data We Process

Webtui Chat processes:

- Account and profile data such as email, username, display name, avatar, and workspace membership.
- Chat content such as messages, reactions, channels, files, attachments, and notification state.
- Device and session data such as app-generated device ID, refresh session, FCM token, platform, app version, and release channel.
- Workspace admin data such as bot, webhook, API token metadata, automation, audit log, and ticket metadata when the user has permission.

## Why We Process Data

- Authenticate users and keep sessions secure.
- Deliver messages, files, notifications, and workspace updates.
- Sync offline cache and retry failed messages safely.
- Support workspace administration, auditability, and security controls.
- Maintain app reliability and compatibility through release metadata.

## Storage And Security

- HTTPS is required for backend traffic.
- Refresh tokens are stored in secure storage.
- Access tokens are kept memory-only by the mobile client.
- Local cache is workspace-scoped.
- App switcher privacy is enabled.
- Logs redact tokens, cookies, passwords, secrets, and API keys.

## User Controls

- Users can manage notification preview and preferences in Settings.
- Users can revoke active sessions.
- Users can clear workspace cache without deleting drafts or outbox.
- Account export/delete endpoint remains a backend requirement before broad public release.

## Contact

Support contact and legal entity details must be finalized before Play Console production submission.

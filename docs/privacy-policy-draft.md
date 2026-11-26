# Privacy Policy Draft

This is an operational draft for Play Console readiness. Legal review is required before public production release.

## Data We Process

Webtui Chat processes:

- Account and profile data such as email, phone number, username, display name,
  avatar, and workspace membership.
- Chat content such as messages, reactions, channels, files, attachments, and notification state.
- Device and session data such as app-generated device ID, refresh session, FCM token, platform, app version, and release channel.
- Workspace admin data such as bot, webhook, API token metadata, automation, audit log, and ticket metadata when the user has permission.

## VPSTTT IDE (Company Server Only, Draft)

On the company's internal server the administrator can enable an embedded VPSTTT
IDE. Opening it sends your name and email to the IDE. You sign in to the IDE on
its own website in your phone's browser, so the chat server does not see your
IDE password, 2FA code, or PIN. What you type, upload, or say in the IDE is
processed by the IDE: speech is turned into text by the company's
speech-recognition service and the audio is not stored; questions are answered
by Claude (Anthropic) or Codex / GPT (OpenAI), depending on the AI account the
company gives you; text you ask to hear is read aloud by the company's voice
service. The IDE keeps your IDE chat history, task prompts, and files until the
project is deleted or you ask for deletion; there is no automatic deletion
period yet. To delete them, contact the IDE platform administrator. The
microphone is used only after you agree and stops when you leave the screen.
Device keys stay in your phone's security chip; for each phone you register,
the IDE keeps your IDE account name, a hash of your email, and the phone's public
keys until you revoke the phone in the IDE screen. Before this section is
published, the IDE operator still has to confirm whether the voice service uses
an outside provider and give a public contact for deletion requests.

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
- Users can initiate permanent account deletion from **Quyền riêng tư -> Xóa tài
  khoản**. The source implements `DELETE /api/v1/users/me` and a public web
  deletion-request page; production deployment, end-to-end deletion testing,
  retention wording, and legal review remain required before release.

## Contact

Support contact, public HTTPS policy URL, data controller/legal entity, retention
periods, subprocessors (including the push relay), deletion/export process, and
regional rights must be finalized and legally reviewed before either public
store submission. This draft is not a publishable legal policy.

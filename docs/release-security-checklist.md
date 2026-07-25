# Mobile Release Security Checklist

Use this checklist before any internal, beta, or production Android release.

## Secrets And Signing

- No `.jks`, `.keystore`, `key.properties`, `.env`, Firebase service account JSON, API key, token, or password is committed.
- GitHub Actions signing secrets are scoped to protected environments.
- Android upload keystore is backed up outside the repo and has an owner.
- Play App Signing is the default plan for production distribution.

## Runtime Privacy

- Refresh token remains in secure storage, access token remains memory-only.
- Logs redact `Authorization`, cookies, access/refresh tokens, passwords, secrets, and API keys.
- App switcher privacy is active through `PrivacyGuard` and Android `FLAG_SECURE`.
- Push payload opens only internal conversation targets and never arbitrary external URLs.
- Notification preview obeys the sensitive preview setting.

## Cache And Tenant Isolation

- Local cache is scoped by workspace where data is tenant-specific.
- Clear cache does not delete message drafts or outbox retries.
- Workspace switch resets runtime scoped state.
- Outbox retry uses `client_message_id`/`Idempotency-Key` to avoid duplicate messages.

## Release Gates

- `dart format --set-exit-if-changed lib test integration_test tool`
- `dart run tool/check_architecture.dart`
- `flutter analyze`
- `flutter test`
- `flutter test integration_test`
- Signed APK/AAB SHA-256 checksum generated and stored with the artifact.
- Mobile release manifest generated for `/mobile/releases` publishing.
- Direct download page reads the same manifest and shows the APK checksum before install.
- `chat.vpsttt.com/download/` and `/downloads/files/` contain only signed APK artifacts, checksums, static page assets, and public metadata.

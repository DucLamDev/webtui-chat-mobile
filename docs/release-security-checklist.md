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

- Third-party GitHub Actions in the release workflow are pinned to reviewed
  immutable commit SHAs; version comments are informational only.
- `dart format --set-exit-if-changed lib test integration_test tool`
- `dart run tool/check_architecture.dart`
- `dart run tool/check_mobile_release.dart`
- `dart run tool/check_production_config.dart --platform=android` with the protected production environment loaded.
- `dart run tool/check_public_release_endpoints.dart --platform=android` after backend/portal deployment.
- `flutter analyze`
- `flutter test`
- `flutter test integration_test`
- Signed APK/AAB SHA-256 checksum generated and stored with the artifact.
- Merged production manifest and 16 KB ZIP/ELF alignment checks pass.
- AAB signature is verified and Play App Signing fingerprints match public `assetlinks.json`.
- The CI upload-key APK is used only for in-job checks and is neither retained
  in the release artifact nor published as a customer download.
- If direct download is enabled, its APK signer exactly matches the Play
  app-signing SHA-256; checksum and manifest are regenerated from that verified
  Play-signed artifact.
- `download.webtui.vn/download/` and `/downloads/files/` contain only verified
  app-signing-key APK artifacts, checksums, static assets, and public metadata.

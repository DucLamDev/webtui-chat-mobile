# WebTUI Android shared-file patch

This directory vendors `receive_sharing_intent` 1.8.1 from pub.dev
(https://pub.dev/packages/receive_sharing_intent, upstream
https://github.com/KasemJaffer/receive_sharing_intent). The Dart API, the iOS
code and the method / event channel names are unchanged; only the Android file
handling differs (the Dart sources only got two lint-only edits so the app's
`flutter analyze` stays clean). The `example/` and `test/` folders of the upstream package are
not vendored.

Changes (`android/src/main/kotlin/com/kasem/receive_sharing_intent/`):

- `FileDirectory.getAbsolutePath` only accepts `content://` URIs. Every accepted
  URI is copied through `ContentResolver` into
  `cacheDir/receive_sharing_intent/<random>/<name>`; `file://` and other schemes
  return `null`. The upstream special cases that returned a computed external
  storage path or a `_data` column are removed.
- The file name comes from `SharedFileNames.sanitize`: last path segment only,
  control and reserved characters removed, leading dots removed, length bounded;
  an empty result falls back to `shared_file.<ext from MIME>`.
- `SharedFileNames.confinedChild` checks the canonical target path stays
  directly inside the share directory before anything is written.
- `toJsonObject` drops a stream URI that could not be copied (keeps the shared
  text, if any). Video thumbnails are written next to the copied file.

The app side (`lib/core/platform/shared_file_path_guard.dart`) only accepts
shared files inside `<temporary directory>/receive_sharing_intent`, which must
stay in sync with `SharedFileNames.SHARE_CACHE_DIR`.

When updating upstream, port these changes and re-run
`test/release/receive_sharing_intent_patch_test.dart` and
`test/core/platform/shared_file_path_guard_test.dart`.

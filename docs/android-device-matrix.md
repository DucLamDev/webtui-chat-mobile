# Android Device Matrix

Use this matrix for Phase M10/M11 manual smoke tests before shipping an internal build.

| Tier | OS/API | Screen | Checks |
|---|---|---|---|
| Low | Android 10-11 | 360x640, 1-2 GB RAM | Login, conversation list, chat send, offline banner, memory while scrolling |
| Mid | Android 12-14 | 390x844, 3-6 GB RAM | Push open, deep link, attachment upload, outbox retry, notification settings |
| High | Android 15+ | 430x932+, 8 GB RAM | Large timeline, image attachments, app background/resume, version gate |
| Tablet | Android 12+ | >= 720 logical width | Adaptive conversation layout, channel detail tabs, keyboard/safe area |
| Accessibility | Any supported OS | Font 1.3x, TalkBack, reduced motion | Message semantics, composer actions, bottom navigation, no text overlap |

Minimum smoke route:

1. Login or open a saved session.
2. Select workspace.
3. Open chat, send text, react, reply, and attach a gallery image.
4. Turn network off, create a failed outbox message, turn network on, retry.
5. Background and resume the app; verify realtime reconnect/catch-up.
6. Open a push/deep link target to a conversation/message.
7. Open Settings, verify version gate and privacy/session screens.
8. Install the signed APK and compare SHA-256 with the published checksum.

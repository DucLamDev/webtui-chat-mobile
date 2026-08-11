# Google Play Reviewer Access Template

Copy the completed instructions into Play Console in English. Never commit the
real password or reusable recovery material.

```text
Publisher reference/reviewer server/domain: REPLACE_IN_PLAY_CONSOLE
Primary username or email: REPLACE_IN_PLAY_CONSOLE
Primary password: REPLACE_IN_PLAY_CONSOLE

Second-user username or email: REPLACE_IN_PLAY_CONSOLE
Second-user password: REPLACE_IN_PLAY_CONSOLE

Moderator username or email: REPLACE_IN_PLAY_CONSOLE
Moderator password: REPLACE_IN_PLAY_CONSOLE

Deletion-test username or email: REPLACE_WITH_SEPARATE_ACCOUNT
Deletion-test password: REPLACE_WITH_SEPARATE_PASSWORD

No OTP, location gate, invitation, or paid subscription is required.

Steps:
1. Open WebTUI Chat.
2. Enter the supplied server/domain manually, complete discovery, and choose Sign in.
3. Enter the username and password above.
4. Select the workspace named "Play Review".
5. The account can access chat, file upload, notifications, calls, profile,
   privacy settings, report content, report user, and block user.

Moderation verification:
1. Sign in as the primary account and open the seeded conversation "Safety review".
2. Long-press the seeded message to report the message or its sender.
3. Open the sender profile to block/unblock the account.
4. Use the supplied moderator account to open the moderation queue and action
   the seeded/test report. Use the second-user account where two active users
   are required; none of these accounts contains real user data.

Account-deletion verification:
1. Use the separate deletion-test account above; do not delete the primary
   reviewer account.
2. Open Settings > Privacy and sessions > Delete account, or use the public
   account-deletion web resource from the Play listing.
3. The deletion-test account is disposable and can be recreated by the
   publisher if the review is repeated.

All supplied credentials remain valid for the review window, do not require OTP, and
do not require access to another account or device. The primary credential is
reusable; the deletion-test credential is intentionally disposable.

The server is operated by the publisher, is reachable globally 24/7, and runs
the same contract as customer self-host instances. Do not point reviewers at a
customer VPS whose availability or data the publisher cannot control.
```

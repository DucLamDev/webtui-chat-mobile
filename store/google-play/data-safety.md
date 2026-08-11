# Google Play Data Safety Source Of Truth

This document describes the production store binary. Reconcile it with the
deployed backend, push relay, SDK inventory, and privacy policy immediately
before every submission. Do not copy answers from a previous release without
checking the actual artifact.

There is one app-level form for the universal package, not one form per customer
instance. Under Play's definition, data is collected when the app or an SDK
transmits it off-device. Data sent to a user-selected self-host server therefore
remains in scope; "self-hosted" is not a valid reason to answer that no data is
collected. The E2EE exception applies only when no intermediary, including the
publisher and instance operator, can read the data; TLS alone does not qualify.

## Security And Deletion Answers

- Data is encrypted in transit: **Yes**. Production permits only HTTPS/WSS.
- Users can request deletion: **Yes**. The app exposes permanent account
  deletion and the store listing links to the public deletion resource.
- Independent security review: answer **No** unless a current, qualifying
  assessment has actually been completed and can be evidenced.
- Ads or data sale: **No** for the current source. Revisit if any monetization
  or advertising SDK is introduced.

## Data Inventory

| Play data type | Required or optional | Purpose | Destination / processor |
| --- | --- | --- | --- |
| Name | Required for an account | Account management and workspace collaboration | Selected WebTUI server |
| Email address | Required for an account | Authentication, account management, and security | Selected WebTUI server |
| User IDs (username and internal account ID) | Required for an account | Authentication, account management, and workspace collaboration | Selected WebTUI server |
| Phone number | Optional, user supplied | Profile and organization directory | Selected WebTUI server |
| Photos and videos | Optional, user initiated | Avatar, attachment, video collaboration | Selected WebTUI server; call peers/TURN when calling |
| Audio files | Optional, user initiated | Voice messages and calls | Selected WebTUI server; call peers/TURN when calling |
| Files and documents | Optional, user initiated | Message attachments and collaboration | Selected WebTUI server |
| Other in-app messages | Optional but core to chat | Messaging, synchronization, notifications | Selected WebTUI server; limited preview through FCM/APNs when enabled |
| Other user-generated content | Optional, user initiated | Reactions, channel/profile content, tasks and collaboration records | Selected WebTUI server |
| App-generated device ID, Firebase installation/push token | Required for a signed-in device when push is enabled | Session security, push registration, idempotency | Selected WebTUI server, push relay, Firebase Cloud Messaging/APNs |
| App interactions | Required | Sync state, notification state, moderation and security audit | Selected WebTUI server |
| Crash logs / diagnostics | Not collected by the current binary | Do not declare until a production diagnostics SDK or upload path is enabled | None currently |
| Precise/approximate location | Not collected | The app does not request Android location permissions | None |
| Advertising ID | Not collected | No advertising SDK is included | None |

Workspace-member names and profiles are server-side collaboration data; the app
does not read the Android address book. Data sent to a server selected by the
user or their organization is still described in the form so the listing
matches observable network behavior. Mark data as "shared" only after applying
Google's current service-provider and user-initiated-action definitions to each
processor. Calls and messages delivered to another participant must be assessed
as sharing in the final Play form even when the transfer was user initiated.

The publisher is the first party shown on the Play listing. An independently
operated customer instance is not automatically the publisher's service provider.
Classify transfers to its operator and to conversation recipients using Google's
current service-provider and user-initiated-action rules, and make the same
publisher/operator boundary explicit in the public privacy policy. The publisher
must separately disclose data processed by its portal, reference/reviewer
instance and official push relay.

## SDK Review

Review the Data Safety guidance for every production dependency, particularly:

- Firebase Core and Firebase Cloud Messaging;
- WebRTC/TURN and incoming-call SDKs;
- image/file pickers and secure storage.

Any future analytics, ads, crash reporting, AI, or attribution SDK requires a
new inventory and an updated Play declaration before rollout.

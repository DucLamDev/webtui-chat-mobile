# Google Play App Content Submission

## Required Answers

- App category: **Business** (use Communication only if the final listing is
  positioned as a general-purpose messenger).
- Contains ads: **No** for the current binary.
- Target audience: organization users, normally **18 and over**. Do not select
  child age groups unless the product and backend are redesigned for Families
  policy compliance.
- User-generated content: **Yes**. Demonstrate Terms acceptance, report message,
  report user, block user, and the operator moderation workflow.
- Account creation: **Yes**. Supply both the in-app deletion path and public
  account-deletion URL.
- Restricted access: **Yes**. Add the reviewer account from
  `reviewer-access.template.md` in Play Console, not in git.
- Ads, government, finance, health, VPN, accessibility, news, and gambling
  declarations: **No**, unless the production feature set changes.

## Artifact Evidence

- Package: `com.vpsttt.webtui_chat`.
- Target API: 36.
- Cleartext traffic and Android backup are disabled.
- Broad storage, media-library, location, contacts, SMS, install-package, and
  battery-optimization permissions are absent from the merged manifest.
- Foreground service and full-screen intent evidence is maintained in
  `foreground-service-declaration.md`.
- Verify Play App Signing and use its SHA-256 certificate in `assetlinks.json`.

## Submission Gate

Do not submit beyond Internal testing until all of the following are green:

1. Privacy, Terms, support, and account-deletion URLs return HTTP 200 with a
   valid public TLS chain.
2. Reviewer credentials work without OTP, geography restrictions, or expiring
   passwords.
3. Report/block flows work against the deployed backend and moderation reports
   can be actioned by an authorized operator.
4. Data Safety matches the production backend and every bundled SDK.
5. The pre-launch report has no blocker crash, ANR, security, accessibility, or
   broken-link finding.

For the universal self-host client, App Access must identify the always-on
publisher reference/reviewer instance and explain that customer domains are
normally entered manually. Data Safety must cover data sent to any selected
instance plus the publisher relay/SDKs; do not create customer-specific answers.
The public privacy policy must distinguish the publisher from each independent
instance operator. Verify both in-app deletion and the external deletion URL,
and demonstrate Terms acceptance, report, block and operator moderation for UGC.

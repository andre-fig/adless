# App Privacy questionnaire notes

This is the review packet for the App Store Connect App Privacy section. It is intentionally a guide, not a claim that the questionnaire has already been saved: the current App Store Connect API does not expose this form.

Official Apple instructions: [Manage app privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/).

## Recommended answers for the current binary

- Data collection: **Yes — diagnostics only.**
- Diagnostics: crash data, performance data, and other technical diagnostics sent to Sentry to improve reliability.
- Tracking: **No**.
- Data linked to the user: **Not linked to the user**; Adless does not create an account, set a Sentry user identity, or send custom identifiers.
- Account creation or login: **None**.
- Advertising or analytics SDK: **None**. Sentry is used only for crash and performance diagnostics.
- Browsing history and DNS queries: **Not collected or retained by Orbe Works
  or sent to Sentry**. Permitted DNS queries are sent to the configured
  third-party DoH providers solely to obtain DNS answers.
- Purchases: StoreKit presents the App Store subscription purchase flow; payment and subscription management are handled by Apple, not by an Adless account or backend.

Adless makes HTTPS requests to the public GitHub Pages blocklist to retrieve a
manifest and a static list. It also sends permitted DNS wire queries over
DNS-over-HTTPS to Cloudflare DNS or Quad9 to obtain answers. These requests are
not associated with an Adless account, are not used for tracking, and Adless
does not retain or send browsing history or DNS query data to Orbe Works or
Sentry. Sentry is configured with default PII collection disabled, network
tracking disabled, and no screenshots or view hierarchy attachments. Recheck
the App Store privacy answers against the final binary and the providers'
current privacy terms before submitting a release.

## Privacy policy

Use:

<https://andre-fig.github.io/adless/privacy>

The policy is part of the landing-page build and is also recorded in `docs/app-store-submission.md`.

## Important verification

Before saving the questionnaire, compare these notes with the final App Store Connect questions and the production binary. Also verify in Sentry project settings that IP-address storage is disabled if that is the intended privacy posture. If a future version adds analytics, login, remote filtering, or any server-side account feature, this questionnaire must be reviewed again.

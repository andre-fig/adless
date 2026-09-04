# App Privacy questionnaire notes

This is the review packet for the App Store Connect App Privacy section. It is intentionally a guide, not a claim that the questionnaire has already been saved: the current App Store Connect API does not expose this form.

Official Apple instructions: [Manage app privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/).

## Recommended answers for the current binary

- Data collection: **Yes — diagnostics and aggregate app-usage statistics.**
- Diagnostics: crash data, performance data, and other technical diagnostics sent to Sentry to improve reliability.
- App usage statistics: an aggregate blocked total associated with an internal installation identifier; no domains, DNS packets, IP addresses, or query history. The service stores only one-way hashes of device-bound DNS/statistics credentials.
- Tracking: **No**.
- Data linked to the user: **Not linked to the user**; Adless does not create an account, set a Sentry user identity, or send custom identifiers.
- Account creation or login: **None**.
- Advertising or analytics SDK: **None**. Sentry is used only for crash and performance diagnostics.
- Browsing history and DNS queries: **Not collected or retained as application
  history by Orbe Works or sent to Sentry**. All DNS selected for Adless passes
  through the Adless HTTPS service; blocked names are not sent to an upstream,
  and permitted queries are sent to Cloudflare DNS or Quad9 solely to obtain DNS
  answers.
- Purchases: StoreKit presents the App Store subscription purchase flow; payment and subscription management are handled by Apple, not by an Adless account or backend.

Adless makes HTTPS requests to the public GitHub Pages blocklist to retrieve a
manifest and a static list. It also sends DNS wire queries over HTTPS to the
Adless DNS service, which applies the blocklist and forwards permitted queries
to Cloudflare DNS or Quad9. The service stores only aggregate blocked totals by
internal installation identifier, not domains or query history. These requests are
not associated with an account and are not used for tracking. Cloudflare may
process technical request metadata under its infrastructure/logging systems;
the Adless application does not enable request logs or send DNS wire data,
domains, URLs, IP addresses, or either credential to Sentry. Sentry is
configured with default PII collection disabled, network tracking disabled, and
no screenshots or view hierarchy attachments. Recheck these answers against
the final binary and the providers' current privacy terms before submitting.

## Privacy policy

Use:

<https://andre-fig.github.io/adless/privacy>

The policy is part of the landing-page build and is also recorded in `docs/app-store-submission.md`.

## Important verification

Before saving the questionnaire, compare these notes with the final App Store Connect questions and the production binary. Also verify in Sentry project settings that IP-address storage is disabled if that is the intended privacy posture. If a future version adds analytics, login, or any account feature, this questionnaire must be reviewed again.

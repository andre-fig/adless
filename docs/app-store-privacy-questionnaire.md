# App Privacy questionnaire notes

This is the review packet for the App Store Connect App Privacy section. It is intentionally a guide, not a claim that the questionnaire has already been saved: the current App Store Connect API does not expose this form.

## Recommended answers for the current binary

- Data collection: **No, we do not collect data from this app.**
- Tracking: **No**.
- Data linked to the user: **None**.
- Account creation or login: **None**.
- Advertising or analytics SDK: **None**.
- Browsing history and DNS queries: **Not collected by Orbe Works**.
- Purchases: StoreKit presents the App Store subscription purchase flow; payment and subscription management are handled by Apple, not by an Adless account or backend.

Adless does make HTTPS requests to the public GitHub Pages blocklist to retrieve a manifest and a static list. Those requests are not associated with an account, are not used for tracking, and the app does not retain or send browsing history or DNS query data to Orbe Works.

## Privacy policy

Use:

<https://andre-fig.github.io/adless/privacy>

The policy is part of the landing-page build and is also recorded in `docs/app-store-submission.md`.

## Important verification

Before saving the questionnaire, compare these notes with the final App Store Connect questions and the production binary. If a future version adds analytics, crash reporting, login, remote filtering, or any server-side account feature, this questionnaire must be reviewed again.

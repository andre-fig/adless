# Adless App Store submission

This document records the App Store Connect preparation for the Orbe Works release.

Last checked: 2026-08-21

## App identity

- App Store Connect app ID: `6803552143`
- Bundle ID: `com.orbeworks.adless`
- SKU: `ADLESS-IOS-ORBEWORKS-001`
- Team ID: `J728Z86KY5`
- Primary locale: `en-US`
- Current app name: `Adless: Clean Web`
- App Store version: `1.0`

## Public URLs

- Landing page: <https://andre-fig.github.io/adless/>
- Privacy policy: <https://andre-fig.github.io/adless/privacy>
- Terms of use: <https://andre-fig.github.io/adless/terms>
- Support: <https://andre-fig.github.io/adless/support>
- Blocklist manifest: <https://andre-fig.github.io/adless/blocklists/manifest.json>

The legal pages are static pages in the landing-page build. They do not require a backend, login, database, or analytics service.

## Store metadata already configured

The English app information and version localization have been populated through the App Store Connect API:

- Subtitle: `Private ad & tracker blocking`
- Keywords: `ad blocker,tracker blocker,dns,privacy,security,browsing`
- Promotional text: `Block ads and trackers locally with one tap.`
- Marketing URL: the landing page above
- Support URL: the support page above
- Privacy policy and privacy choices URLs: the privacy page above
- Description: describes on-device DNS Proxy protection, no account, no remote VPN server, local blocklist updates, and the two paid plans.

The first version does not have a “What’s New” field. App Store Connect does not allow that field for the first version.

## Subscriptions

Subscription group: `Adless Pro`

| Plan | Product ID | Price in Brazil | Introductory offer |
| --- | --- | --- | --- |
| Monthly | `com.orbeworks.adless.pro.monthly` | R$4.90 | 7-day free trial for eligible new subscribers |
| Annual | `com.orbeworks.adless.pro.yearly` | R$29.90 | 7-day free trial for eligible new subscribers |

The plans are English-only, have review notes, availability in Brazil, and the introductory offers configured. Their upfront prices are set in Brazil and equalized across all 175 Apple territories so the products satisfy first-submission pricing validation. The existing subscription review screenshots are complete. The subscription group version and both subscription versions are included in the review submission.

## Build and signing

- Build `2` is uploaded, processing state `VALID`, and linked to App Store version `1.0`.
- The repository build number is now `2` for the app and DNS proxy extension.
- The app uses the existing Network Extension and App Group entitlements.
- `ITSAppUsesNonExemptEncryption` is set to `false` because the app uses standard system HTTPS and SHA-256 validation, not a custom encryption implementation. The same value was also declared on build `2` through the App Store Connect API.

Build locally:

```sh
xcodebuild archive \
  -project apps/ios/Adless.xcodeproj \
  -scheme Adless \
  -destination 'generic/platform=iOS' \
  -archivePath /tmp/Adless.xcarchive

xcodebuild -exportArchive \
  -archivePath /tmp/Adless.xcarchive \
  -exportOptionsPlist /tmp/AdlessExportOptions.plist \
  -exportPath /tmp/Adless-export
```

The archive is already uploaded and build `2` is valid. A future build must use a new monotonically increasing build number.

## Review information

The age-rating declaration has been filled for a utility app with no advertising, user-generated content, messaging, social features, gambling, sexual content, or unrestricted web access.

The production app review detail is filled with the account holder’s contact information and states that no demo account is required. No login or test account exists. The review notes explain the subscription, Network Extension permission, on-device DNS proxy, and offline fallback flow.

Suggested review notes:

> Adless is an on-device DNS Proxy that blocks matching ad and tracker domains. The app does not use an account or a remote VPN server. To test the main flow, install the app, open the subscription sheet, select either plan, complete the App Store sandbox purchase, then tap the central button. The button can also turn protection off. The app keeps a validated blocklist locally and falls back to it when the network is unavailable.

## Final App Store Connect checklist

- [x] App identity, bundle ID, SKU, and primary locale
- [x] English store metadata
- [x] Privacy policy, terms, and support URLs
- [x] Age-rating declaration
- [x] Monthly and annual products
- [x] Brazil prices and 7-day introductory offers
- [x] Subscription review screenshots
- [x] Processed iPhone App Store screenshot (`1242 x 2688`)
- [x] Processed iPad App Store screenshot (`2048 x 2732`)
- [x] Upload and select build `2`
- [x] Set the primary category to Utilities
- [x] Set content rights declaration
- [x] Set app copyright
- [x] Set the app price schedule to free
- [x] Set build export-compliance value to non-exempt encryption `false`
- [x] Add production app review contact details and notes
- [x] Complete and publish the App Privacy questionnaire in App Store Connect
- [x] Add the app version, subscription group, monthly product, and annual product to the review submission
- [ ] Confirm Paid Apps Agreement, banking, and tax information
- [x] Submit the app version for review

The current App Store Connect API specification does not expose the App Privacy questionnaire. It was completed and published in the App Store Connect web interface. The current binary uses Sentry only for crash and performance diagnostics; it does not have an account, advertising SDK, tracking, user-generated content, or browsing-history collection. The app makes HTTPS requests to the static GitHub Pages blocklist only to retrieve a manifest/list, and does not associate those requests with an identity. Recheck the App Privacy questionnaire after every SDK change.

Official instructions: [Manage app privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/).

The App Store Connect review submission was accepted on 2026-08-21 and is now `WAITING_FOR_REVIEW`. The app version, subscription group version, monthly subscription version, and annual subscription version all report `READY_FOR_REVIEW`.

## App Store Connect API state

- App ID: `6803552143`
- Version ID: `e8e4cb87-8885-4c99-9a8b-e3c3474813b8`
- Build ID: `10c2d829-2050-4925-83c4-9520beb8a6d8`
- Review submission ID: `33b0457c-19be-46cb-a80c-5542539e2ca6`
- Review submission state: `WAITING_FOR_REVIEW`
- Submitted date: `2026-08-22T00:44:08.448Z`
- Subscription group version `7ad49d18-17f3-4056-99bc-47c26ddd8120`: review item `READY_FOR_REVIEW`
- Monthly subscription version `db4440ac-5372-4290-8f84-aed6644c5336`: review item `READY_FOR_REVIEW`
- Annual subscription version `09694ee5-73ff-4f6f-9fc6-da1a7de00f6a`: review item `READY_FOR_REVIEW`
- App Store version `e8e4cb87-8885-4c99-9a8b-e3c3474813b8`: review item `READY_FOR_REVIEW`
- App encryption declaration: created and linked to build `2`
- App Store screenshots: iPhone and iPad reservations both `COMPLETE`

The App Store Connect API has no endpoint for the App Privacy questionnaire in the current official OpenAPI specification. The remaining account-level checks (Paid Apps Agreement, banking, and tax) also belong to the Account Holder in App Store Connect and cannot be safely inferred or completed by the repository.

## Screenshot source

The checked-in screenshot was captured from the iOS simulator and resized to Apple’s accepted 6.5-inch dimensions:

- `docs/app-store/screenshots/iphone-main.png`
- `docs/app-store/screenshots/ipad-main.png`
- Dimensions: iPhone `1242 x 2688`; iPad `2048 x 2732`

They show the English interface and the fallback/offline-safe state. Both reservations were accepted and finished processing in App Store Connect.

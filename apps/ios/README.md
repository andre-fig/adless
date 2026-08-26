# Adless iOS app

Adless is a system-wide DNS sinkhole for iOS built with SwiftUI and a NetworkExtension DNS Proxy. It blocks ads and trackers locally without routing traffic through an external VPN server.

## Targets

- `Adless` (iOS app, SwiftUI)
- `AdlessDNSProxy` (DNS proxy extension)
- `AdlessTests` (XCTest para parser, gzip, fallback e atualização)

## Build & Run

1. From the monorepo root, open `apps/ios/Adless.xcodeproj` in Xcode.
2. Select `Adless Dev` for local development. It uses `Debug Dev` by default
   and installs as a separate app named **Adless Dev**.
3. Select `Adless` for the official app. Its `Debug` and `Release`
   configurations always use the App Store/TestFlight identifiers.
4. Set a valid Team and configure the matching App Group and Network
   Extensions (DNS Proxy) identifiers in the Apple Developer portal.
5. Run on a compatible device. The simulator can build the code, but full DNS
   interception requires a real device.

### Build environments

The values are centralized in `Configurations/Production.xcconfig` and
`Configurations/Development.xcconfig`; the Swift runtime reads the generated
Info.plist values through `Shared/BuildEnvironment.swift`.

| Scheme | Configuration | App ID | DNS Proxy ID | App Group | Display name |
| --- | --- | --- | --- | --- | --- |
| `Adless Dev` | `Debug Dev` / `Release Dev` | `com.orbeworks.adless.dev` | `com.orbeworks.adless.dev.dnsproxy` | `group.com.orbeworks.adless.dev` | Adless Dev |
| `Adless` | `Debug` / `Release` | `com.orbeworks.adless` | `com.orbeworks.adless.dnsproxy` | `group.com.orbeworks.adless` | Adless |

Both the app and extension use the same environment-specific App Group. This
keeps blocklists, subscription snapshots, counters, DNS proxy state, and
other persisted data separate. No source file should hardcode an App Group or
provider identifier.

For an official archive, select the `Adless` scheme and archive the `Release`
configuration. Never archive `Adless Dev` for TestFlight or the App Store.

## Blocklist update behavior

The landing page publishes the static files generated at the monorepo root:

- `https://andre-fig.github.io/adless/blocklists/manifest.json`
- `https://andre-fig.github.io/adless/blocklists/blocklist.txt.gz`
- `https://andre-fig.github.io/adless/blocklists/blocklist.txt`

The app embeds `SeedBlocklist.txt`, copies it to the shared Application Support
directory on first launch, and keeps the latest valid local copy there. Opening
the app or returning to the foreground starts a background manifest check,
subject to a 24-hour interval and exponential retry backoff. The activate
button uses the local list immediately and never depends on the network. A
download is only installed after HTTPS, size, gzip, SHA-256, syntax, and domain
count checks pass; failures never disable an active proxy.

The app group path used by the app and extension is
`Library/Application Support/Blocklists/blocklist.txt`. The extension replaces
its active file only through atomic rename, so it cannot observe a partial
write. The app group and Network Extension entitlement still require matching
configuration in the Apple Developer portal before device distribution.

The DNS proxy needs a real device for full interception; simulator limitations apply.

## Encrypted DNS forwarding

Blocked names are answered locally from the active `Set<String>` blocklist.
Permitted DNS wire packets are sent with an HTTPS `POST` using the
`application/dns-message` media type. The production order is:

1. Cloudflare DoH: `https://cloudflare-dns.com/dns-query`;
2. Quad9 DoH: `https://dns.quad9.net/dns-query`.

The Network Extension creates one ephemeral `URLSession` per DNS proxy
provider instance and shares it between Cloudflare and Quad9. The system
validates the TLS certificate and hostname and negotiates HTTP/2 when the
provider requires it; the app does not use certificate pinning or disable
validation. If the proxy observes the URLSession resolving either DoH
hostname, it answers only that provider's A/AAAA bootstrap query locally.
This explicit public-API guard prevents a recursive loop without relying on
plaintext DNS or private Network Extension behavior.

Each permitted query is handled concurrently and has a 1.5-second request and
resource timeout. A transport, TLS, HTTP, empty-body, or invalid-DNS response
from Cloudflare causes a retry through Quad9, sequentially for that query. A
valid DNS response such as `NXDOMAIN` is returned directly. After three
consecutive primary failures, a 15-second circuit breaker sends new queries
directly to Quad9; the breaker resets when the network path changes or the
interval expires. If both encrypted providers fail, the extension returns a
local `SERVFAIL` promptly. There is deliberately no plaintext UDP/TCP port 53
fallback.

The extension keeps only aggregate in-memory latency diagnostics: sample count,
success/failure count, duration, and provider. It never stores or logs the
queried domain, DNS wire body, transaction ID, or response payload.

The app does not send queries, logs, metrics, or browsing history to an Orbe
Works backend (there is no backend). The configured DNS providers receive the
permitted DNS wire queries needed to answer them; see the in-app and hosted
privacy policies for that third-party processing detail.

Unit tests use HTTP mocks. An optional live smoke test can be run from the
repository root with:

```sh
python3 tools/dns/smoke_doh.py
```

It validates both official endpoints without being part of the normal XCTest
suite.

## Subscription

The app uses StoreKit 2 and does not have a subscription backend or user login.
The product identifiers expected by the app are:

- `com.orbeworks.adless.pro.monthly`;
- `com.orbeworks.adless.pro.yearly`.

Create both auto-renewable products in one Subscription Group in App Store
Connect and configure a 7-day free Introductory Offer for eligible new
subscribers. The offer is enforced by App Store Connect; the app only displays
the offer and verifies the signed StoreKit entitlement.

The subscription manager checks `Transaction.currentEntitlements`, listens to
`Transaction.updates`, and restores purchases with `AppStore.sync()`. Active
and grace-period entitlements are persisted atomically in the existing App
Group at `Library/Application Support/Subscription/subscription-state.json`.
The DNS proxy reads that state and refuses to start or process DNS flows after
the entitlement expires. No personal identity or payment data is stored by the
app.

### Local subscription testing

The shared `Adless` scheme is configured with `Adless.storekit`. It contains
both production product identifiers, the Brazilian prices, the same subscription
group, and a one-week local introductory offer. This lets the paywall and
entitlement flow be tested before App Store review and without a real charge.

In Xcode, select the `Adless` scheme and run the app. Use **Debug > StoreKit >
Manage Transactions** to inspect or reset purchases. The local configuration
is only for development; TestFlight and production continue to use the
products configured in App Store Connect.

For fast layout work, a direct Debug launch of the iOS Simulator (for example
with `simctl`) displays the two local subscription options immediately. Those
options are display-only; purchase testing must use the shared Xcode scheme,
which passes `-useStoreKitProducts` and loads the real StoreKit test products.
This simulator-only fallback is excluded from Release builds and physical
devices.

Enable Billing Grace Period in App Store Connect after testing it in Sandbox.
The first auto-renewable subscription must be submitted together with an app
version for review. Product metadata, prices, availability, the Subscription
Group, the 7-day offer, and the App Store agreement are external App Store
Connect configuration and cannot be completed from this repository alone.

## Localization

The app uses the String Catalog at
`Adless/Resources/Localizable.xcstrings`. English (`en`) is the source
language, Brazilian Portuguese (`pt-BR`), and Spanish (`es`) are currently
included. iOS selects
the first supported language in the user’s preferred language list and falls
back to English when no translation is available.

When adding another language, add its localization to the String Catalog and
the project’s known regions, then add the same language to the StoreKit product
metadata in App Store Connect. Keep product prices and trial eligibility in
StoreKit/App Store Connect; the app only formats and displays the values
returned by Apple. Legal documents, accessibility labels, subscription
messages, and the simulator StoreKit configuration are localized alongside the
main interface.

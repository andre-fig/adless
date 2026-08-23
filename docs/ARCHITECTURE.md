# Adless architecture

## Overview

Adless is a native iOS app that blocks advertising and tracking domains at the
DNS layer. It has no application backend, user account, payment server, or
custom VPN server.

The repository contains three cooperating areas:

```text
                 weekly GitHub Actions job
                         │
                         ▼
OISD Small ──► Python generator ──► GitHub Pages static files
                                           │
                                           ▼
                              iOS blocklist update service
                                           │
                         App Group shared application data
                                           │
                                           ▼
                 DNS Proxy Network Extension on the iPhone
```

The landing page and blocklist distribution are static. The app has no
backend. For permitted DNS queries, the Network Extension uses encrypted
DNS-over-HTTPS directly with the configured public resolvers.

## Repository structure

```text
apps/
├── ios/
│   ├── Adless/              SwiftUI app and application services
│   ├── AdlessDNSProxy/      DNS Proxy Network Extension
│   ├── AdlessTests/         XCTest target
│   └── Adless.xcodeproj/    Xcode project and schemes
└── landing-page/            React + Vite + TypeScript landing page

tools/
└── blocklists/              Python generator, validator, fixtures, tests

docs/                        Operational and App Store documentation
```

## iOS runtime

### Application

The `Adless` target is a SwiftUI application. `AppViewModel` coordinates the
main state and connects the UI to these services:

- `SubscriptionManager`: loads StoreKit 2 products, observes transactions,
  restores purchases, and persists the verified entitlement snapshot;
- `BlocklistManager`: initializes the embedded seed and coordinates updates;
- `VPNManager`: configures and starts or stops `NEDNSProxyManager`;
- `BlockingStatsStore`: reads and displays local blocked-request counters.

On launch, the app first prepares the blocklist and checks the existing DNS
proxy status. This allows an already-active protection session to open directly
in the active state. Returning to the foreground refreshes subscription state,
DNS status, statistics, and—when allowed by the refresh policy—the remote
blocklist.

The activation button uses the local list immediately. It never waits for an
internet update and never disables protection because a list update failed.

### DNS Proxy extension

`AdlessDNSProxy` implements `NEDNSProxyProvider` with the existing DNS Proxy
capability. The app configures it with:

- primary DoH endpoint: `https://cloudflare-dns.com/dns-query`;
- fallback DoH endpoint: `https://dns.quad9.net/dns-query`;
- App Group: `group.com.orbeworks.adless`.

The extension:

1. verifies the shared subscription snapshot before starting or accepting a
   flow;
2. loads the active blocklist into a `Set<String>`;
3. retains each accepted UDP or TCP flow handler for its lifetime;
4. opens and continuously reads the client flow;
5. normalizes the queried domain and checks the complete name plus each parent
   domain in the set;
6. returns a local blocked DNS response for blocked names;
7. forwards allowed DNS wire queries to the primary DoH endpoint over HTTPS;
8. retries the fallback DoH endpoint after timeout, transport/TLS/HTTP failure,
   empty body, or invalid DNS payload;
9. returns DNS `SERVFAIL` when both encrypted providers fail instead of leaving the
   client query without a response.

UDP handlers retain the client flow and continue reading datagrams. TCP handlers
parse length-prefixed DNS messages, maintain a bounded response buffer, and use
the same block/forward decision. Allowed requests are resolved concurrently;
writes are associated with their original flow request, and cancellation closes
the corresponding task.

### DNS-over-HTTPS transport

`Adless/Services/DNSDoHTransport.swift` separates upstream transport from the
flow handlers:

- `DNSDoHTransport` validates the original DNS wire query, creates an HTTP POST
  with `Content-Type` and `Accept` set to `application/dns-message`, and accepts
  only a successful HTTP response with a structurally valid DNS message that
  preserves the transaction ID and question count;
- `DNSUpstreamResolver` owns the primary/fallback policy. A valid `NXDOMAIN`
  is returned normally and does not trigger fallback;
- `URLSessionDNSDoHHTTPClient` uses an ephemeral `URLSession` over HTTPS. The
  system validates the certificate and hostname, and negotiates HTTP/2 when
  the provider requires it; the app does not use certificate pinning or an
  insecure delegate;
- the session has no URL cache, cookies, credentials, or persistent storage.
  Each request has a bounded timeout and the task is canceled when its flow
  ends;
- if the proxy observes the session resolving `cloudflare-dns.com` or
  `dns.quad9.net`, `DNSDoHEndpoint.bootstrapResponse(for:)` answers only the
  matching A/AAAA bootstrap query locally. This explicit public-API guard is
  the recursion-avoidance mechanism; the implementation does not assume that
  `URLSession` is automatically excluded from the DNS proxy.

The extension never sends an upstream query to UDP/TCP port 53, and it never
falls back to plaintext DNS.

This is DNS interception, not traffic tunneling. Adless does not see or proxy
HTTP request bodies, TLS traffic, passwords, or page content. It receives DNS
queries from the system and sends permitted DNS wire packets to Cloudflare DNS
or Quad9 over HTTPS. The configured providers can process those permitted
queries to produce answers; Adless does not send them to an Orbe Works server,
and does not send them to Sentry.

### Shared App Group data

The app and extension use the existing App Group rather than `Documents`:

```text
group.com.orbeworks.adless/
└── Library/Application Support/
    ├── Blocklists/
    │   ├── blocklist.txt
    │   ├── blocklist.txt.gz
    │   ├── manifest.json
    │   └── update-state.json
    ├── BlockingStats/
    │   └── blocking-stats.json
    └── Subscription/
        └── subscription-state.json
```

Writes are atomic and use iOS file protection. The DNS extension can therefore
observe either a complete old file or a complete new file, never a partial
write.

## Blocklist distribution

### Source and generation

The MVP source is the official OISD Small endpoint declared in
`tools/blocklists/sources.json`:

```text
https://small.oisd.nl/
```

The Python pipeline uses only the standard library. It downloads over HTTPS,
accepts the configured source format, normalizes domains to canonical ASCII
DNS names, applies `tools/blocklists/allowlist.txt`, removes duplicates, and
sorts deterministically.

The pipeline rejects empty or suspicious responses, HTML/JSON error pages,
invalid domains, oversized inputs, and abnormal changes. It generates artifacts
in a temporary directory and replaces published files only after validation.

The same generator creates the embedded iOS fallback seed. The seed is not a
second source of truth and is not manually maintained in Swift.

### Published artifacts

The landing page publishes these files under `/blocklists/`:

```text
manifest.json
blocklist.txt.gz
blocklist.txt
blocklist.sha256
```

The public manifest URL is:

```text
https://andre-fig.github.io/adless/blocklists/manifest.json
```

The manifest contains the schema version, content-derived version, generated
timestamp, relative payload URL, compressed and uncompressed sizes, domain
count, source metadata, and SHA-256. The SHA-256 is the digest of
`blocklist.txt.gz`, not the uncompressed text. Content-derived versioning keeps
timestamp-only changes from creating commits.

### iOS update flow

`BlocklistUpdateService` checks the manifest at most once every 24 hours and
uses `ETag` and `Last-Modified` when the hosting layer provides them. Failures
use exponential backoff.

For a new list, the service:

1. fetches and validates the HTTPS manifest;
2. resolves the relative payload URL against the known Pages origin;
3. downloads the gzip payload with size limits;
4. verifies the compressed SHA-256;
5. decompresses and validates the canonical list and domain count;
6. atomically installs the text, compressed payload, and manifest.

The old valid list remains active until every step succeeds. A `304 Not
Modified`, an unchanged content hash, an offline device, or an invalid remote
payload does not replace local data.

## Subscriptions and access control

Subscriptions are sold exclusively through App Store Connect and StoreKit 2:

```text
com.orbeworks.adless.pro.monthly
com.orbeworks.adless.pro.yearly
```

Both products belong to one subscription group and use the seven-day
introductory offer configured in App Store Connect. Prices and trial eligibility
come from StoreKit/App Store configuration; the app does not determine whether
Apple has charged the customer.

The app verifies transactions and stores a small entitlement snapshot in the
App Group. The snapshot contains entitlement status, product identifier,
expiry, grace-period state, and verification time. The extension reads this
snapshot before starting and periodically rechecks it. An expired or missing
entitlement prevents DNS blocking from starting; it does not require a
backend.

## Landing page

`apps/landing-page` is a static React + Vite application. Its `public/`
directory is copied into the generated site, so blocklist artifacts remain
directly downloadable and are not bundled into JavaScript.

GitHub Pages publishes the production build at:

```text
https://andre-fig.github.io/adless/
```

The legal routes used by the app include `/terms` and `/privacy`. Hosting,
cache validation, `ETag`, and `Last-Modified` behavior are provided by GitHub
Pages when available.

## Automation and delivery

The repository uses `develop → pull request → main`.

| Workflow | Trigger | Runner | Responsibility |
| --- | --- | --- | --- |
| `ios-tests.yml` | Pull request or manual | macOS | iOS XCTest validation |
| `release-ios.yml` | Relevant `main` push or manual | macOS | App Store archive, App Store Connect upload, and submission |
| `update-blocklist.yml` | Weekly schedule or manual | Ubuntu | Generate, validate, and commit blocklist artifacts when changed |
| `deploy-pages.yml` | Relevant `main` push or manual | Ubuntu | Build and deploy the landing page to GitHub Pages |

All workflows use concurrency cancellation, explicit timeouts, least-privilege
permissions, and explicit file paths. The release workflow does not repeat the
PR iOS test job; local `pre-push` and PR validation cover that check before the
release archive.

The release workflow requires only these GitHub Actions secrets:

- `ASC_KEY_ID`;
- `ASC_ISSUER_ID`;
- `ASC_PRIVATE_KEY`.

The `.p8` key is materialized only in the runner's temporary directory and is
never committed or logged.

## Failure and recovery behavior

- **Remote blocklist unavailable:** keep the last valid local list or the
  embedded seed; protection remains usable offline.
- **Invalid or suspicious blocklist:** reject it before installation and retain
  the previous version.
- **Primary DoH provider unavailable or invalid:** try Quad9 over DoH.
- **Both DoH providers unavailable:** return `SERVFAIL` promptly; do not leave
  the client flow waiting indefinitely and do not use plaintext DNS.
- **Subscription expired:** StoreKit state is refreshed, the extension stops
  accepting DNS flows, and the UI requests renewed access.
- **Workflow failure before commit:** no generated artifacts are published.
- **Workflow failure after an Apple upload:** inspect App Store Connect before
  retrying; the preflight prevents duplicate submissions for versions already
  under review.

## Change guide

Use the narrowest validation for the changed area:

```sh
# Landing page
npm run lint
npm run typecheck
npm run build:landing

# Blocklist
python3 -m unittest discover -s tools/blocklists/tests -v
python3 tools/blocklists/generate_blocklist.py --sync-seed
python3 tools/blocklists/validate_blocklist.py
python3 tools/blocklists/validate_blocklist.py \
  --seed apps/ios/Adless/Resources/SeedBlocklist.txt

# iOS
xcodebuild -project apps/ios/Adless.xcodeproj \
  -scheme AdlessTests \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  CODE_SIGNING_ALLOWED=NO test

# Workflows
actionlint .github/workflows/*.yml
```

Do not manually edit generated blocklist artifacts, commit secrets, broaden
entitlements without checking both iOS targets, or add a service that changes
the static/no-backend architecture without an explicit product decision.

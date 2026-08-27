# Adless repository instructions

## Repository shape

- `apps/ios/`: SwiftUI app and XCTest target;
- `apps/dns-worker/`: Cloudflare Worker RFC 8484 and Durable Object stats;
- `apps/landing-page/`: static React + Vite + TypeScript site;
- `tools/blocklists/`: deterministic Python generator, validator, fixtures and tests;
- `tools/dns-worker/`: generated edge bundle preparation.

Read `AGENTS.md` and the README for the area being changed before editing.
Preserve unrelated working-tree changes and keep the task scoped.

## Architectural boundaries

The iOS app configures Apple encrypted DNS with
`NEDNSSettingsManager`/`NEDNSOverHTTPSSettings`. The Worker applies the
blocklist at the edge and forwards only allowed DNS wire messages to Cloudflare
DoH then Quad9 on transient failure. It is not a general traffic proxy.

Do not add accounts, login, a payment backend, remote receipt validation, DNS
UDP, plaintext fallback, a network interface, traffic routes or private APIs.
Purchases remain StoreKit 2/App Store Connect. Prefer existing dependencies and
the standard library. Never commit secrets, keys, profiles, certificates or
build products.

## iOS rules

Targets in `apps/ios/Adless.xcodeproj` are `Adless` and `AdlessTests`. The only
Network Extension capability is `dns-settings`. `isEnabled` is read-only; save
the configuration, reload preferences, and reflect the actual system state.
Handle foreground, restart, network changes, manual removal and expired
subscription without a persisted fake protection flag.

The installation token is 32 random bytes in Keychain
`AfterFirstUnlockThisDeviceOnly`; it is not derived from IDFA, IDFV, Apple
Account or hardware. Never log it. Do not store a DNS list in the app bundle or
an App Group; the edge artifact is the source of filtering.

## Worker rules

Keep RFC 8484 wire transport (`application/dns-message`), strict size/method/
header validation, transaction ID and EDNS preservation, exact plus suffix
matching, and a finite in-memory cache bounded by received TTL. Valid DNS
errors such as NXDOMAIN are final responses and do not trigger fallback.
Fallback is sequential and HTTPS-only. Do not log QNAME, DNS payload, token or
IP. Stats store only a numeric increment and aggregate total.

Worker tests must use mocks and cover malformed messages, all relevant query
types, blocked/allowed names, allowlist, cache, concurrency, rate limit,
fallback, SERVFAIL and blocklist integrity.

## Blocklist rules

The enabled source is the official OISD Small source in
`tools/blocklists/sources.json`; allowlist handling remains declarative. The
generator creates the public landing artifacts and the Worker copy. Do not
edit generated files manually or execute downloaded content.

```sh
python3 -m unittest discover -s tools/blocklists/tests -v
python3 tools/blocklists/generate_blocklist.py --sync-worker
python3 tools/dns-worker/prepare_blocklist.py
python3 tools/blocklists/validate_blocklist.py
```

## Commands and automation

```sh
npm ci
npm run lint
npm run typecheck
npm run build:landing
npm run build:dns-worker
npm run test:dns-worker
```

Keep workflow concurrency, timeouts, least-privilege permissions and explicit
generated paths. The Worker deployment uses only
`CLOUDFLARE_API_TOKEN`/`CLOUDFLARE_ACCOUNT_ID`; iOS distribution uses the
documented App Store Connect secrets. Run `actionlint` when available.

Before delivery, run `git diff --check`, relevant tests, iOS build/XCTest, and
the archive/IPA checks in `tools/ios/`. Do not claim deployment or distribution
success without observing it.

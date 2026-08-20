# Adless iOS app

Adless is a system-wide DNS sinkhole for iOS built with SwiftUI and a NetworkExtension DNS Proxy. It blocks ads and trackers locally without routing traffic to external VPN servers.

## Targets

- `Adless` (iOS app, SwiftUI)
- `AdlessDNSProxy` (DNS proxy extension)
- `AdlessTests` (XCTest para parser, gzip, fallback e atualização)

## Build & Run

1. From the monorepo root, open `apps/ios/Adless.xcodeproj` in Xcode.
2. Set a valid Team and the existing App Group identifier
   `group.com.usefulish.adless` for both `Adless` and `AdlessDNSProxy`.
3. Ensure the App ID has App Groups and Network Extensions (DNS Proxy)
   enabled. The project does not create or manage Apple Developer accounts.
4. Select the `Adless` scheme and run on a compatible device. The simulator
   can build the code, but full DNS interception requires a real device.

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

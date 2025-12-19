# Adless

Adless is a system-wide DNS sinkhole for iOS built with SwiftUI and a NetworkExtension DNS Proxy. It blocks ads and trackers locally without routing traffic to external VPN servers.

## Features

- Local-only DNS proxy using `NEDNSProxyProvider`
- Blocklists in hosts format (OISD, Energized, StevenBlack, etc.)
- Manual and automatic updates (stub for weekly refresh)
- Whitelist support
- Upstream resolvers: Cloudflare (1.1.1.1) and Google (8.8.8.8)
- App Group shared blocklist cache

## Targets

- `Adless` (iOS app, SwiftUI)
- `AdlessDNSProxy` (DNS proxy extension)

## Architecture (textual)

- UI (SwiftUI): `AdlessApp` → `ContentView` bound to `AppViewModel`
- Managers: `VPNManager` (NEDNSProxyManager enable/disable), `BlocklistManager` (download/parse/cache), `WhitelistStore` (UserDefaults)
- Models: `BlocklistSource`, `WhitelistEntry`
- Network Extension: `DNSProxyProvider` + `DNSMessage` parser running in `AdlessDNSProxy` target
- Shared data: App Group `group.com.adless.shared` storing `blocklist.txt`

## App Store Compliance

- Uses only public NetworkExtension APIs
- VPN is local; does not change IP/geolocation
- No analytics, login, or data collection
- `NSNetworkExtensionUsageDescription` explains local DNS filtering

## Build & Run

1. Open `Adless.xcodeproj` in Xcode.
2. Set a valid Team and App Group identifier `group.com.adless.shared` for both targets (app + extension).
3. Ensure Signing & Capabilities include Network Extensions (DNS Proxy) and App Group.
4. Select the `Adless` scheme and run on iOS 15+ device or simulator.

## Notes

- The DNS proxy needs a real device for full interception; simulator limitations apply.
- Packet handling is simplified; production apps should implement full DNS parsing and error handling.

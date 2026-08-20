# Adless iOS app

Adless is a system-wide DNS sinkhole for iOS built with SwiftUI and a NetworkExtension DNS Proxy. It blocks ads and trackers locally without routing traffic to external VPN servers.

## Targets

- `Adless` (iOS app, SwiftUI)
- `AdlessDNSProxy` (DNS proxy extension)

## Build & Run

1. From the monorepo root, open `apps/ios/Adless.xcodeproj` in Xcode.
2. Set a valid Team and App Group identifier `group.com.adless.shared` for both targets.
3. Ensure Signing & Capabilities include Network Extensions (DNS Proxy) and App Group.
4. Select the `Adless` scheme and run on an iOS 15+ device or simulator.

The DNS proxy needs a real device for full interception; simulator limitations apply.

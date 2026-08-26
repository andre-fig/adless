# Adless architecture

Adless is an on-device DNS filter. It has no account, backend, Adless DNS
server, or remote VPN server. The iOS app embeds the blocklist fallback and
uses a local `NEPacketTunnelProvider` only to receive DNS packets.

## Runtime topology

```text
system DNS client
      │ UDP/TCP 53 to synthetic DNS addresses
      ▼
PacketTunnelProvider
      ├── local blocklist Set and suffix matcher
      │       └── A/AAAA/NODATA response for blocked names
      └── HTTPS DoH URLSession for permitted DNS wire messages
              ├── Cloudflare DNS
              └── Quad9 fallback
```

The Packet Tunnel has split routing: it includes only `10.255.255.2/32` and
`fd00:ad1e:55::53/128`, the synthetic DNS endpoints configured in
`NEDNSSettings`. It does not install `0.0.0.0/0` or `::/0`. Therefore ordinary
application traffic and the extension’s HTTPS connection to the upstream
providers use the underlying network path. Any unexpected non-DNS packet that
reaches the flow is ignored without inspecting its payload.

## Targets and identifiers

| Environment | App ID | Packet Tunnel ID | App Group | Display name |
| --- | --- | --- | --- | --- |
| Production / TestFlight | `com.orbeworks.adless` | `com.orbeworks.adless.tunnel` | `group.com.orbeworks.adless` | Adless |
| Development | `com.orbeworks.adless.dev` | `com.orbeworks.adless.dev.tunnel` | `group.com.orbeworks.adless.dev` | Adless Dev |

The Xcode project contains only `Adless`, `PacketTunnel`, and `AdlessTests`.
The app embeds only `PacketTunnel.appex`. The environment-specific App Group
keeps configuration, blocklists, counters, and subscription snapshots apart
when development and production are installed together.

The app and extension both use the `packet-tunnel-provider` and App Groups
entitlements. The extension’s `Info.plist` declares
`com.apple.networkextension.packet-tunnel` and
`PacketTunnelProvider` as its principal class.

## Lifecycle and state

`VPNManager` is an actor. Activation loads or creates the matching
`NETunnelProviderManager`, configures `NETunnelProviderProtocol`, saves it,
reloads preferences, and starts `NETunnelProviderSession`. Deactivation calls
`stopVPNTunnel()`. The UI reads `manager.connection.status`; it does not use a
persisted boolean. Status notifications update the UI for connecting,
connected, reasserting, disconnecting, disconnected, and invalid states.

The extension loads the atomically installed blocklist once at startup. The
app sends a `reloadBlocklist` provider message after a validated update, so a
running extension can refresh its in-memory `Set` without a restart. If the
message is unavailable, the next tunnel lifecycle loads the latest complete
file. Subscription access is read from the verified App Group snapshot; an
expired or absent snapshot keeps the tunnel in encrypted pass-through mode.

## DNS processing

`DNSMessage` validates DNS headers, question names, compressed names, resource
record framing, EDNS data, and length bounds without imposing a type whitelist.
`DNSDomainMatcher` normalizes ASCII/Punycode names and checks the complete name
and each parent suffix in a hash set. No file or `UserDefaults` access happens
per query.

`DNSPacket` safely parses IPv4 and IPv6 packets, including common IPv6 extension
headers, UDP/53, and TCP/53. `DNSPacketWriter` swaps endpoints and calculates
IPv4, UDP, IPv6, and TCP checksums for local replies. TCP/53 supports the DNS
length prefix, multiple in-flight frames, bounded buffers, SYN/ACK/FIN/RST
state, and ordered response writes. Fragmented packets are not processed by
the small DNS path and are not forwarded as application traffic.

Blocked queries are answered locally: A receives `0.0.0.0`, AAAA receives the
zero IPv6 address, and other types receive valid NODATA. They never reach an
upstream. Permitted queries are passed unchanged to the existing
`DNSUpstreamResolver`, which uses one ephemeral URL session, Cloudflare as the
primary provider, Quad9 as fallback, bounded timeouts, response validation,
controlled retry, and a network-reset circuit breaker.

The resolver answers A/AAAA bootstrap queries for the two DoH hostnames from
the static endpoint address set. This is an explicit recursion guard. Because
the DoH destination routes are not included in the Packet Tunnel, the HTTPS
connection itself cannot loop back through Adless; the bootstrap answer also
prevents the system resolver from needing an upstream plaintext DNS path.

## Shared data and privacy

```text
Library/Application Support/
├── Blocklists/blocklist.txt
├── Blocklists/blocklist.txt.gz
├── Blocklists/manifest.json
├── Blocklists/update-state.json
├── BlockingStats/blocking-stats.json
└── Subscription/subscription-state.json
```

Blocklist and state writes are atomic and protected until first user
authentication. Blocking counters are accumulated in memory and flushed in
batches, on a moderate timer, and when the extension stops.

Sentry receives only lifecycle/error diagnostics. Event tags include operation,
NSError domain/code, sanitized localized description, and VPN status. DNS
queries, hostnames, URLs, accessed IP addresses, payloads, and browsing history
are not sent or logged. Release archives generate dSYMs for both
`Adless.app` and `PacketTunnel.appex`; CI uploads the archive symbol directory
when `SENTRY_AUTH_TOKEN` is configured.

## Portal requirements

Create or update these Apple Developer identifiers and capabilities:

1. `com.orbeworks.adless` and `com.orbeworks.adless.dev` as App IDs with App
   Groups and Network Extensions / Packet Tunnel enabled.
2. `com.orbeworks.adless.tunnel` and
   `com.orbeworks.adless.dev.tunnel` as extension App IDs with the same
   corresponding App Group and Packet Tunnel provider capability.
3. Keep the production and development App Groups separate as listed above.
4. Regenerate development/distribution provisioning profiles after the
   capability and identifier changes. No MDM or private entitlement is used.

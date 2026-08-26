import Foundation

/// Values injected by the active Xcode build configuration.
///
/// This file is compiled into both the app and the Packet Tunnel extension so
/// every process resolves the same environment-specific identifiers from its
/// own generated Info.plist.
enum BuildEnvironment {
    nonisolated static let bundleIdentifier = Bundle.main.bundleIdentifier ?? "Adless"
    nonisolated static let appGroupIdentifier = requiredInfoValue("AdlessAppGroupIdentifier")
    nonisolated static let packetTunnelBundleIdentifier = requiredInfoValue("AdlessPacketTunnelBundleIdentifier")
    nonisolated static let displayName = requiredInfoValue("AdlessDisplayName")

    nonisolated private static func requiredInfoValue(_ key: String) -> String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty,
              !value.contains("$(") else {
            preconditionFailure("Missing build-configured Info.plist value: \(key)")
        }
        return value
    }
}

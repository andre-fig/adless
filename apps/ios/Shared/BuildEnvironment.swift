import Foundation

/// Values injected by the active Xcode build configuration.
enum BuildEnvironment {
    nonisolated static let bundleIdentifier = Bundle.main.bundleIdentifier ?? "Adless"
    nonisolated static let displayName = requiredInfoValue("AdlessDisplayName")
    nonisolated static let dnsCloudBaseURL = requiredInfoValue("AdlessDNSCloudBaseURL")

    nonisolated private static func requiredInfoValue(_ key: String) -> String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty,
              !value.contains("$(") else {
            preconditionFailure("Missing build-configured Info.plist value: \(key)")
        }
        return value
    }
}

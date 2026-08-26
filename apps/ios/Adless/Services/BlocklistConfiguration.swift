import Foundation

enum BlocklistConfiguration {
    static let manifestURL = URL(string: "https://andre-fig.github.io/adless/blocklists/manifest.json")!
    static let appGroupIdentifier = BuildEnvironment.appGroupIdentifier
    static let refreshInterval: TimeInterval = 24 * 60 * 60
    static let maximumManifestBytes = 256 * 1024
    static let maximumPayloadBytes = 25 * 1024 * 1024
    static let maximumDomainCount = 200_000
    static let embeddedSeedName = "SeedBlocklist"
}

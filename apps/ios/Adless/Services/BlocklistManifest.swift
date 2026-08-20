import Foundation

struct BlocklistManifest: Codable, Equatable {
    struct Source: Codable, Equatable {
        let id: String
        let name: String
    }

    let schemaVersion: Int
    let version: String
    let generatedAt: String
    let file: String
    let downloadUrl: String
    let compression: String
    let sha256: String
    let sizeBytes: Int
    let uncompressedSizeBytes: Int
    let domainCount: Int
    let sources: [Source]

    func validate() throws {
        guard schemaVersion == 1,
              file == "blocklist.txt.gz",
              downloadUrl == "blocklist.txt.gz",
              compression == "gzip",
              version.range(of: #"^v[0-9a-f]{16}$"#, options: .regularExpression) != nil,
              sha256.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil,
              sizeBytes > 0,
              sizeBytes <= BlocklistConfiguration.maximumPayloadBytes,
              uncompressedSizeBytes > 0,
              uncompressedSizeBytes <= BlocklistConfiguration.maximumPayloadBytes,
              domainCount > 0,
              domainCount <= BlocklistConfiguration.maximumDomainCount else {
            throw BlocklistUpdateError.invalidManifest
        }

        guard let generatedDate = ISO8601DateFormatter().date(from: generatedAt), generatedDate <= Date().addingTimeInterval(300) else {
            throw BlocklistUpdateError.invalidManifest
        }
    }
}

enum BlocklistUpdateError: LocalizedError {
    case invalidManifest
    case insecureURL
    case invalidResponse
    case payloadTooLarge
    case checksumMismatch
    case invalidGzip
    case invalidBlocklist
    case countMismatch
    case unavailableSeed
    case notModifiedWithoutValidCache

    var errorDescription: String? {
        switch self {
        case .invalidManifest: return "Invalid blocklist manifest"
        case .insecureURL: return "Insecure blocklist URL"
        case .invalidResponse: return "Invalid blocklist response"
        case .payloadTooLarge: return "Blocklist payload is too large"
        case .checksumMismatch: return "Blocklist checksum mismatch"
        case .invalidGzip: return "Invalid gzip blocklist"
        case .invalidBlocklist: return "Invalid blocklist"
        case .countMismatch: return "Blocklist count mismatch"
        case .unavailableSeed: return "Embedded blocklist is unavailable"
        case .notModifiedWithoutValidCache: return "Unchanged blocklist has no valid local cache"
        }
    }
}

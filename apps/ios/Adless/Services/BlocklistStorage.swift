import Foundation
import Darwin
import os.log

struct BlocklistUpdateState: Codable {
    var lastCheckAt: Date?
    var failureCount: Int = 0
    var nextRetryAt: Date?
    var etag: String?
    var lastModified: String?
    var manifestVersion: String?
    var manifestSHA256: String?
}

final class BlocklistStorage {
    private let fileManager: FileManager
    private let embeddedSeedData: Data?
    private let baseDirectory: URL?

    init(fileManager: FileManager = .default, embeddedSeedData: Data? = nil, baseDirectory: URL? = nil) {
        self.fileManager = fileManager
        self.embeddedSeedData = embeddedSeedData
        self.baseDirectory = baseDirectory
    }

    func ensureEmbeddedSeed() throws -> Set<String> {
        if let active = try? loadActive() {
            return active
        }
        guard let seed = embeddedSeedData ?? loadBundleSeed() else {
            throw BlocklistUpdateError.unavailableSeed
        }
        let entries = try BlocklistParser.parseCanonical(seed)
        try atomicWrite(seed, to: activeURL)
        return entries
    }

    func loadActive() throws -> Set<String> {
        let data = try Data(contentsOf: activeURL)
        return try BlocklistParser.parseCanonical(data)
    }

    func hasValidActive() -> Bool {
        (try? loadActive()) != nil
    }

    func storedManifest() -> BlocklistManifest? {
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(BlocklistManifest.self, from: data),
              (try? manifest.validate()) != nil else { return nil }
        return manifest
    }

    func updateState() -> BlocklistUpdateState {
        guard let data = try? Data(contentsOf: stateURL),
              let state = try? JSONDecoder().decode(BlocklistUpdateState.self, from: data) else {
            return BlocklistUpdateState()
        }
        return state
    }

    func saveUpdateState(_ state: BlocklistUpdateState) throws {
        let data = try JSONEncoder().encode(state)
        try atomicWrite(data, to: stateURL)
    }

    func install(canonical: Data, compressed: Data, manifest: Data) throws {
        _ = try BlocklistParser.parseCanonical(canonical)
        // Publish the active text first and the manifest last. If the process
        // stops between atomic replacements, the old manifest cannot falsely
        // certify a new version; the next check simply retries it.
        try atomicWrite(canonical, to: activeURL)
        try atomicWrite(compressed, to: compressedURL)
        try atomicWrite(manifest, to: manifestURL)
        // The extension reads only the atomically replaced active text file. It
        // can see either a complete old list or a complete new list, never a partial one.
    }

    private var rootURL: URL {
        if let baseDirectory { return baseDirectory }
        if let group = fileManager.containerURL(forSecurityApplicationGroupIdentifier: BlocklistConfiguration.appGroupIdentifier) {
            return group.appendingPathComponent("Library/Application Support/Blocklists", isDirectory: true)
        }
        let support = (try? fileManager.url(for: .applicationSupportDirectory,
                                            in: .userDomainMask,
                                            appropriateFor: nil,
                                            create: true)) ?? fileManager.temporaryDirectory
        return support.appendingPathComponent("Adless/Blocklists", isDirectory: true)
    }

    private var activeURL: URL { rootURL.appendingPathComponent("blocklist.txt") }
    private var compressedURL: URL { rootURL.appendingPathComponent("blocklist.txt.gz") }
    private var manifestURL: URL { rootURL.appendingPathComponent("manifest.json") }
    private var stateURL: URL { rootURL.appendingPathComponent("update-state.json") }

    private func loadBundleSeed() -> Data? {
        guard let url = Bundle.main.url(forResource: BlocklistConfiguration.embeddedSeedName, withExtension: "txt") else {
            return nil
        }
        return try? Data(contentsOf: url)
    }

    private func atomicWrite(_ data: Data, to destination: URL) throws {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let temporary = rootURL.appendingPathComponent(".\(destination.lastPathComponent).\(UUID().uuidString).tmp")
        do {
            // The filename is already unique and lives beside the destination;
            // avoiding a second Foundation-level atomic write keeps the final
            // replace operation a single rename.
            try data.write(to: temporary)
            guard rename(temporary.path, destination.path) == 0 else {
                throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: destination.path])
            }
            try? fileManager.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: destination.path)
        } catch {
            try? fileManager.removeItem(at: temporary)
            os_log("Blocklist atomic write failed: %{public}@", log: .default, type: .error, error.localizedDescription)
            throw error
        }
    }
}

import Foundation
import os.log

struct SubscriptionStorage {
    private let fileManager: FileManager
    private let baseDirectory: URL?

    init(fileManager: FileManager = .default, baseDirectory: URL? = nil) {
        self.fileManager = fileManager
        self.baseDirectory = baseDirectory
    }

    func load() -> SubscriptionAccessSnapshot? {
        guard let data = try? Data(contentsOf: stateURL) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(SubscriptionAccessSnapshot.self, from: data)
    }

    func save(_ snapshot: SubscriptionAccessSnapshot) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try atomicWrite(encoder.encode(snapshot), to: stateURL)
    }

    private var rootURL: URL {
        if let baseDirectory { return baseDirectory }
        let support = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.temporaryDirectory
        return support
            .appendingPathComponent("Adless", isDirectory: true)
            .appendingPathComponent(SubscriptionConfiguration.subscriptionDirectoryName, isDirectory: true)
    }

    private var stateURL: URL {
        rootURL.appendingPathComponent(SubscriptionConfiguration.subscriptionStateFileName)
    }

    private func atomicWrite(_ data: Data, to destination: URL) throws {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        do {
            try data.write(to: destination, options: .atomic)
            try? fileManager.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: destination.path
            )
        } catch {
            os_log("Subscription state write failed: %{public}@", log: .default, type: .error, error.localizedDescription)
            throw error
        }
    }
}

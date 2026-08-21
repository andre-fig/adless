import Foundation

final class BlocklistManager {
    private let storage: BlocklistStorage
    private let updater: BlocklistUpdateService
    private(set) var blocklist: Set<String> = []

    init(session: URLSession = .shared, storage: BlocklistStorage = BlocklistStorage()) {
        self.storage = storage
        self.updater = BlocklistUpdateService(session: session, storage: storage)
        blocklist = (try? storage.ensureEmbeddedSeed()) ?? (try? storage.loadActive()) ?? []
    }

    var cachedCount: Int {
        blocklist.count
    }

    func ensureActiveBlocklist() throws -> Int {
        // The active list is loaded during initialization and refreshed after a
        // validated remote update. Re-parsing the full list on every tap blocks
        // the main actor and makes activation feel frozen.
        guard blocklist.isEmpty else { return blocklist.count }
        blocklist = try storage.ensureEmbeddedSeed()
        return blocklist.count
    }

    func refreshIfNeeded() async -> BlocklistRefreshResult? {
        do {
            let result = try await updater.refreshIfNeeded()
            blocklist = (try? storage.loadActive()) ?? blocklist
            return result
        } catch {
            // The embedded or last valid list remains active. The updater logs
            // the failure and applies backoff without surfacing technical data.
            return nil
        }
    }
}

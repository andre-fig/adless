import Foundation

final class BlocklistManager {
    private let appGroup = "group.com.usefulish.adless"
    private let blocklistFilename = "blocklist.txt"
    private let seedFilename = "SeedBlocklist"
    private let session: URLSession
    private(set) var blocklist: Set<String> = []

    init(session: URLSession = .shared) {
        self.session = session
        loadCachedBlocklist()
    }

    var cachedCount: Int {
        blocklist.count
    }

    func updateBlocklists(sources: [BlocklistSource]) async throws -> Int {
        var aggregated = loadSeed()

        for source in sources where source.isEnabled {
            let (data, _) = try await session.data(from: source.url)
            if let body = String(data: data, encoding: .utf8) {
                aggregated.formUnion(parseHosts(body))
            }
        }

        blocklist = aggregated
        try persist(list: aggregated)
        return aggregated.count
    }

    private func parseHosts(_ content: String) -> Set<String> {
        var domains: Set<String> = []
        let separators = CharacterSet.whitespaces

        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, trimmed.hasPrefix("#") == false else { continue }
            let parts = trimmed.components(separatedBy: separators).filter { !$0.isEmpty }
            guard let candidate = parts.last else { continue }
            let normalized = candidate.lowercased()
            if normalized.contains(".") {
                domains.insert(normalized)
            }
        }
        return domains
    }

    private func loadSeed() -> Set<String> {
        guard let url = Bundle.main.url(forResource: seedFilename, withExtension: "txt"),
              let contents = try? String(contentsOf: url) else {
            return []
        }
        return parseHosts(contents)
    }

    private func persist(list: Set<String>) throws {
        let destination = try containerURL().appendingPathComponent(blocklistFilename)
        let body = list.sorted().joined(separator: "\n")
        try body.write(to: destination, atomically: true, encoding: .utf8)
    }

    private func loadCachedBlocklist() {
        guard let content = try? String(contentsOf: containerURL().appendingPathComponent(blocklistFilename)) else { return }
        blocklist = Set(content.components(separatedBy: .newlines).filter { !$0.isEmpty })
    }

    private func containerURL() throws -> URL {
        if let appGroupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) {
            return appGroupURL
        }

        // Fallback for simulator/no App Group provisioning: use Application Support.
        let support = try FileManager.default.url(for: .applicationSupportDirectory,
                                                  in: .userDomainMask,
                                                  appropriateFor: nil,
                                                  create: true)
        let fallback = support.appendingPathComponent("AdlessFallback", isDirectory: true)
        try FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
        return fallback
    }
}

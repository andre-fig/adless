import Foundation

struct WhitelistEntry: Identifiable, Codable, Hashable {
    let id: UUID
    let domain: String
}

final class WhitelistStore {
    private let key = "whitelist"
    private let defaults = UserDefaults.standard

    private(set) var entries: [WhitelistEntry] = []

    init() {
        load()
    }

    func add(domain: String) {
        let set = Set(entries.map { $0.domain })
        guard set.contains(domain) == false else { return }
        entries.append(WhitelistEntry(id: UUID(), domain: domain))
        persist()
    }

    func remove(domain: String) {
        entries.removeAll { $0.domain == domain }
        persist()
    }

    private func load() {
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([WhitelistEntry].self, from: data) {
            entries = decoded
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: key)
        }
    }
}

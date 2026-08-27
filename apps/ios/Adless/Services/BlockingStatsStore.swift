import Foundation
import os.log

struct BlockingStatsSnapshot: Codable, Equatable {
    let dayKey: String
    var todayCount: Int
    var allTimeCount: Int
    var dayBaselineTotal: Int?

    init(dayKey: String, todayCount: Int, allTimeCount: Int, dayBaselineTotal: Int? = nil) {
        self.dayKey = dayKey
        self.todayCount = todayCount
        self.allTimeCount = allTimeCount
        self.dayBaselineTotal = dayBaselineTotal
    }

    static func empty(for dayKey: String) -> BlockingStatsSnapshot {
        BlockingStatsSnapshot(dayKey: dayKey, todayCount: 0, allTimeCount: 0, dayBaselineTotal: nil)
    }
}

/// Stores only the last known cloud total and a local day baseline. The edge
/// service remains authoritative; this cache keeps the existing counter UI
/// useful while the device is offline and prevents visible decreases.
struct BlockingStatsStore {
    private let fileManager: FileManager
    private let baseDirectory: URL?
    private let fixedNow: Date?

    init(fileManager: FileManager = .default, baseDirectory: URL? = nil, now: Date? = nil) {
        self.fileManager = fileManager
        self.baseDirectory = baseDirectory
        self.fixedNow = now
    }

    func read() -> BlockingStatsSnapshot {
        let today = Self.dayKey(for: fixedNow ?? Date())
        guard let data = try? Data(contentsOf: stateURL),
              let snapshot = try? JSONDecoder().decode(BlockingStatsSnapshot.self, from: data),
              snapshot.todayCount >= 0,
              snapshot.allTimeCount >= 0 else {
            return .empty(for: today)
        }

        guard snapshot.dayKey == today else {
            let rolledOver = BlockingStatsSnapshot(
                dayKey: today,
                todayCount: 0,
                allTimeCount: snapshot.allTimeCount,
                dayBaselineTotal: snapshot.allTimeCount
            )
            try? save(rolledOver)
            return rolledOver
        }
        return snapshot
    }

    @discardableResult
    func updateRemoteTotal(_ remoteTotal: Int) -> BlockingStatsSnapshot {
        let previous = read()
        let total = max(previous.allTimeCount, max(0, remoteTotal))
        let baseline = previous.dayBaselineTotal
            ?? (previous.allTimeCount == 0 && previous.todayCount == 0
                ? total
                : max(0, previous.allTimeCount - previous.todayCount))
        let today = max(previous.todayCount, max(0, total - baseline))
        let next = BlockingStatsSnapshot(
            dayKey: previous.dayKey,
            todayCount: today,
            allTimeCount: total,
            dayBaselineTotal: baseline
        )
        try? save(next)
        return next
    }

    func save(_ snapshot: BlockingStatsSnapshot) throws {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(snapshot)
        let temporary = rootURL.appendingPathComponent(".blocking-stats-\(UUID().uuidString).tmp")
        do {
            try data.write(to: temporary)
            guard rename(temporary.path, stateURL.path) == 0 else {
                throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: stateURL.path])
            }
            try? fileManager.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: stateURL.path
            )
        } catch {
            try? fileManager.removeItem(at: temporary)
            os_log("Blocking stats cache write failed: %{public}@", log: .default, type: .error, error.localizedDescription)
            throw error
        }
    }

    static func dayKey(for date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
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
            .appendingPathComponent("BlockingStats", isDirectory: true)
    }

    private var stateURL: URL {
        rootURL.appendingPathComponent("blocking-stats.json")
    }
}

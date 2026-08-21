import Foundation
import os.log

struct BlockingStatsSnapshot: Codable, Equatable {
    let dayKey: String
    var todayCount: Int
    var allTimeCount: Int

    static func empty(for dayKey: String) -> BlockingStatsSnapshot {
        BlockingStatsSnapshot(dayKey: dayKey, todayCount: 0, allTimeCount: 0)
    }
}

struct BlockingStatsStore {
    private let fileManager: FileManager
    private let baseDirectory: URL?
    private let fixedNow: Date?

    init(
        fileManager: FileManager = .default,
        baseDirectory: URL? = nil,
        now: Date? = nil
    ) {
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
                allTimeCount: snapshot.allTimeCount
            )
            try? save(rolledOver)
            return rolledOver
        }

        return snapshot
    }

    func save(_ snapshot: BlockingStatsSnapshot) throws {
        let data = try JSONEncoder().encode(snapshot)
        try atomicWrite(data, to: stateURL)
    }

    static func dayKey(for date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = String(components.year ?? 0).leftPadded(to: 4)
        let month = String(components.month ?? 0).leftPadded(to: 2)
        let day = String(components.day ?? 0).leftPadded(to: 2)
        return "\(year)-\(month)-\(day)"
    }

    private var rootURL: URL {
        if let baseDirectory { return baseDirectory }
        if let group = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.orbeworks.adless"
        ) {
            return group
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Application Support", isDirectory: true)
                .appendingPathComponent("BlockingStats", isDirectory: true)
        }

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

    private func atomicWrite(_ data: Data, to destination: URL) throws {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        do {
            try data.write(to: destination, options: .atomic)
            try? fileManager.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: destination.path
            )
        } catch {
            os_log("Blocking stats write failed: %{public}@", log: .default, type: .error, error.localizedDescription)
            throw error
        }
    }
}

private extension String {
    func leftPadded(to length: Int) -> String {
        guard count < length else { return self }
        return String(repeating: "0", count: length - count) + self
    }
}

final class BlockingStatsRecorder: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.orbeworks.adless.blocking-stats", qos: .utility)
    private let store: BlockingStatsStore

    private var snapshot: BlockingStatsSnapshot?
    private var pendingCount = 0
    private var scheduledFlush: DispatchWorkItem?

    init(store: BlockingStatsStore = BlockingStatsStore()) {
        self.store = store
    }

    func recordBlockedRequest() {
        queue.async { [weak self] in
            guard let self else { return }

            let today = BlockingStatsStore.dayKey(for: Date())
            if self.snapshot?.dayKey != today {
                self.snapshot = self.store.read()
                self.pendingCount = 0
            }

            guard var snapshot = self.snapshot else { return }
            if snapshot.todayCount < Int.max {
                snapshot.todayCount += 1
            }
            if snapshot.allTimeCount < Int.max {
                snapshot.allTimeCount += 1
            }
            self.snapshot = snapshot
            self.pendingCount += 1

            if self.pendingCount >= 20 {
                self.flushOnQueue()
            } else {
                self.scheduleFlushOnQueue()
            }
        }
    }

    func flush() {
        queue.sync {
            flushOnQueue()
        }
    }

    private func scheduleFlushOnQueue() {
        guard scheduledFlush == nil else { return }
        let workItem = DispatchWorkItem { [weak self] in
            self?.flushOnQueue()
        }
        scheduledFlush = workItem
        queue.asyncAfter(deadline: .now() + 2, execute: workItem)
    }

    private func flushOnQueue() {
        scheduledFlush?.cancel()
        scheduledFlush = nil
        guard pendingCount > 0, let snapshot else { return }

        do {
            try store.save(snapshot)
            pendingCount = 0
        } catch {
            os_log("Blocking stats flush failed: %{public}@", log: .default, type: .error, error.localizedDescription)
            scheduleFlushOnQueue()
        }
    }

    deinit {
        flush()
    }
}

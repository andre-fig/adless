import Foundation

struct DNSResolutionResult: Sendable {
    let response: Data
    let wasBlocked: Bool
}

/// Performs the local policy decision before delegating permitted DNS wire
/// messages to the existing encrypted upstream resolver.
final class PacketTunnelDNSService: @unchecked Sendable {
    private let resolver: DNSUpstreamResolver
    private let lock = NSLock()
    private var blocklist: Set<String> = []
    private var filteringEnabled = false

    init(resolver: DNSUpstreamResolver = .production()) {
        self.resolver = resolver
    }

    func update(blocklist: Set<String>, filteringEnabled: Bool) {
        lock.lock()
        self.blocklist = blocklist
        self.filteringEnabled = filteringEnabled
        lock.unlock()
    }

    func resolve(_ query: Data) async -> DNSResolutionResult {
        guard let message = DNSMessage(data: query) else {
            return DNSResolutionResult(
                response: DNSMessage.serverFailureResponse(id: query.dnsIdentifier),
                wasBlocked: false
            )
        }

        guard !message.isResponse else {
            return DNSResolutionResult(response: query, wasBlocked: false)
        }

        let (shouldFilter, entries) = policySnapshot()

        if shouldFilter,
           let name = message.firstQuestionName(),
           DNSDomainMatcher.matches(domain: name, entries: entries) {
            return DNSResolutionResult(response: message.blockedResponse(), wasBlocked: true)
        }

        if let bootstrap = DNSDoHEndpoint.bootstrapResponse(for: query) {
            return DNSResolutionResult(response: bootstrap, wasBlocked: false)
        }

        do {
            return DNSResolutionResult(response: try await resolver.resolve(query), wasBlocked: false)
        } catch {
            PacketTunnelTelemetry.error(error, operation: "doh.error")
            return DNSResolutionResult(response: message.serverFailureResponse(), wasBlocked: false)
        }
    }

    private func policySnapshot() -> (filteringEnabled: Bool, blocklist: Set<String>) {
        lock.lock()
        defer { lock.unlock() }
        return (filteringEnabled, blocklist)
    }
}

final class PacketTunnelSubscriptionAccess: @unchecked Sendable {
    private let appGroupIdentifier = BuildEnvironment.appGroupIdentifier
    private let statePath = "Library/Application Support/Subscription/subscription-state.json"
    private let lock = NSLock()
    private var checkedAt = Date.distantPast
    private var cachedValue = false
    private var cachedEffectiveUntil: Date?

    func hasAccess(now: Date = Date()) -> Bool {
        lock.lock()
        if now.timeIntervalSince(checkedAt) < 30 {
            let result = cachedValue && (cachedEffectiveUntil ?? .distantPast) > now
            lock.unlock()
            return result
        }
        lock.unlock()

        let result = readAccess(now: now)
        lock.lock()
        checkedAt = now
        cachedValue = result.isEntitled
        cachedEffectiveUntil = result.effectiveUntil
        lock.unlock()
        return result.isEntitled
    }

    private func readAccess(now: Date) -> (isEntitled: Bool, effectiveUntil: Date?) {
        guard let group = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else { return (false, nil) }
        let url = group.appendingPathComponent(statePath)
        guard let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder.iso8601.decode(
                  SharedSubscriptionSnapshot.self,
                  from: data
              ) else { return (false, nil) }
        return (
            snapshot.isEntitled && (snapshot.effectiveUntil ?? .distantPast) > now,
            snapshot.effectiveUntil
        )
    }
}

private struct SharedSubscriptionSnapshot: Decodable {
    let isEntitled: Bool
    let effectiveUntil: Date?
}

private extension JSONDecoder {
    static let iso8601: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

private extension Data {
    var dnsIdentifier: UInt16 {
        guard count >= 2 else { return 0 }
        return UInt16(self[startIndex]) << 8 | UInt16(self[index(startIndex, offsetBy: 1)])
    }
}

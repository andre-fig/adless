import Foundation
import Network
import NetworkExtension
import os

private let dnsLogger = Logger(subsystem: "com.orbeworks.adless", category: "dns-proxy")

final class DNSProxyProvider: NEDNSProxyProvider {
    private let appGroupIdentifier = "group.com.orbeworks.adless"
    private let subscriptionStatePath = "Library/Application Support/Subscription/subscription-state.json"
    private let flowLock = NSLock()
    private let upstreamResolver = DNSUpstreamResolver.production

    private var blocklist: Set<String> = []
    private var subscriptionState: SharedSubscriptionAccessSnapshot?
    private var subscriptionStateCheckedAt = Date.distantPast
    private var activeFlows: [ObjectIdentifier: DNSProxyFlowHandling] = [:]
    private let statsRecorder = BlockingStatsRecorder()

    override func startProxy(options: [String: Any]? = nil, completionHandler: @escaping (Error?) -> Void) {
        dnsLogger.info("DNS proxy start requested")
        if hasSubscriptionAccess() {
            loadBlocklist()
            dnsLogger.info("DNS proxy started with \(self.blocklist.count, privacy: .public) domains and encrypted upstreams")
        } else {
            // Keep DNS forwarding available after entitlement expiry. An empty
            // blocklist makes the flow handlers pass every query to DoH instead
            // of discarding the flow and breaking the user's internet access.
            blocklist = []
            dnsLogger.info("DNS proxy started in encrypted pass-through mode: subscription inactive")
        }
        completionHandler(nil)
    }

    override func stopProxy(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        dnsLogger.info("DNS proxy stopping")
        flowLock.lock()
        let flows = Array(activeFlows.values)
        flowLock.unlock()

        guard !flows.isEmpty else {
            statsRecorder.flush()
            completionHandler()
            return
        }

        let group = DispatchGroup()
        flows.forEach { flow in
            group.enter()
            flow.close {
                group.leave()
            }
        }
        group.notify(queue: .global(qos: .userInitiated)) { [weak self] in
            self?.statsRecorder.flush()
            completionHandler()
        }
    }

    override func handleNewFlow(_ flow: NEAppProxyFlow) -> Bool {
        let filteringEnabled = hasSubscriptionAccess()
        // A lapsed entitlement must not turn a DNS failure into an internet
        // outage. Supported flows still use encrypted DoH with no blocklist.
        let flowBlocklist = filteringEnabled ? blocklist : []

        let identifier = ObjectIdentifier(flow)
        if let udpFlow = flow as? NEAppProxyUDPFlow {
            dnsLogger.debug("New UDP DNS flow received; filtering enabled: \(filteringEnabled, privacy: .public)")
            let handler = DNSUDPFlowHandler(
                flow: udpFlow,
                blocklist: flowBlocklist,
                resolver: upstreamResolver,
                onClose: { [weak self] in self?.removeFlow(identifier) },
                onBlocked: { [weak self] in self?.statsRecorder.recordBlockedRequest() }
            )
            retainFlow(handler, identifier: identifier)
            handler.start()
            return true
        }

        if let tcpFlow = flow as? NEAppProxyTCPFlow {
            dnsLogger.debug("New TCP DNS flow received; filtering enabled: \(filteringEnabled, privacy: .public)")
            let handler = DNSTCPFlowHandler(
                flow: tcpFlow,
                blocklist: flowBlocklist,
                resolver: upstreamResolver,
                onClose: { [weak self] in self?.removeFlow(identifier) },
                onBlocked: { [weak self] in self?.statsRecorder.recordBlockedRequest() }
            )
            retainFlow(handler, identifier: identifier)
            handler.start()
            return true
        }

        dnsLogger.debug("Unsupported DNS flow rejected")
        return false
    }

    private func retainFlow(_ handler: DNSProxyFlowHandling, identifier: ObjectIdentifier) {
        flowLock.lock()
        activeFlows[identifier] = handler
        flowLock.unlock()
    }

    private func removeFlow(_ identifier: ObjectIdentifier) {
        flowLock.lock()
        activeFlows.removeValue(forKey: identifier)
        flowLock.unlock()
    }

    private func loadBlocklist() {
        guard let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            blocklist = []
            return
        }

        let current = group.appendingPathComponent("Library/Application Support/Blocklists/blocklist.txt")
        let legacy = group.appendingPathComponent("blocklist.txt")
        guard let content = (try? String(contentsOf: current, encoding: .utf8))
                ?? (try? String(contentsOf: legacy, encoding: .utf8)) else {
            blocklist = []
            return
        }

        blocklist = Set(content.components(separatedBy: .newlines).compactMap(Self.normalize))
    }

    private func hasSubscriptionAccess() -> Bool {
        let now = Date()
        if now.timeIntervalSince(subscriptionStateCheckedAt) < 30,
           let subscriptionState {
            return subscriptionState.isEntitled && (subscriptionState.effectiveUntil ?? .distantPast) > now
        }

        subscriptionStateCheckedAt = now
        guard let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            subscriptionState = nil
            return false
        }

        let url = group.appendingPathComponent(subscriptionStatePath)
        guard let data = try? Data(contentsOf: url) else {
            subscriptionState = nil
            return false
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        subscriptionState = try? decoder.decode(SharedSubscriptionAccessSnapshot.self, from: data)
        guard let subscriptionState else { return false }
        return subscriptionState.isEntitled && (subscriptionState.effectiveUntil ?? .distantPast) > now
    }

    static func normalize(_ value: String) -> String? {
        let candidate = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
        guard !candidate.isEmpty,
              !candidate.contains("*"),
              !candidate.contains("/"),
              !candidate.contains("|"),
              !candidate.contains("^"),
              !candidate.contains(":"),
              candidate.count <= 253,
              candidate.contains("."),
              !reservedNames.contains(candidate),
              !isIPAddress(candidate),
              candidate.unicodeScalars.allSatisfy({ $0.value < 128 }) else {
            return nil
        }

        let labels = candidate.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.allSatisfy({ label in
            guard !label.isEmpty,
                  label.count <= 63,
                  let first = label.first,
                  let last = label.last,
                  isASCIIAlphaNumeric(first),
                  isASCIIAlphaNumeric(last) else {
                return false
            }
            return label.allSatisfy { isASCIIAlphaNumeric($0) || $0 == "-" }
        }) else {
            return nil
        }
        return candidate
    }

    private static let reservedNames: Set<String> = [
        "localhost",
        "localhost.localdomain",
        "broadcasthost",
        "ip6-allnodes",
        "ip6-allrouters",
        "ip6-localhost"
    ]

    private static func isASCIIAlphaNumeric(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first, character.unicodeScalars.count == 1 else {
            return false
        }
        return (scalar.value >= 48 && scalar.value <= 57)
            || (scalar.value >= 65 && scalar.value <= 90)
            || (scalar.value >= 97 && scalar.value <= 122)
    }

    private static func isIPAddress(_ value: String) -> Bool {
        let parts = value.split(separator: ".")
        return parts.count == 4 && parts.allSatisfy { Int($0) != nil }
    }
}

private struct SharedSubscriptionAccessSnapshot: Decodable {
    let isEntitled: Bool
    let effectiveUntil: Date?
}

import NetworkExtension
import os.log

final class DNSProxyProvider: NEDNSProxyProvider {
    private var blocklist: Set<String> = []
    private var subscriptionState: SharedSubscriptionAccessSnapshot?
    private var subscriptionStateCheckedAt = Date.distantPast
    private let upstreamPrimary = "1.1.1.1"
    private let upstreamSecondary = "8.8.8.8"
    private let appGroupKey = "appGroup"
    private let appGroupIdentifier = "group.com.usefulish.adless"
    private let subscriptionStatePath = "Library/Application Support/Subscription/subscription-state.json"

    override func startProxy(options: [String : Any]? = nil, completionHandler: @escaping (Error?) -> Void) {
        guard hasSubscriptionAccess() else {
            completionHandler(DNSProxyError.subscriptionInactive)
            return
        }
        loadBlocklist()
        completionHandler(nil)
    }

    override func stopProxy(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        completionHandler()
    }

    override func handleNewFlow(_ flow: NEAppProxyFlow) -> Bool {
        // DNS flows only
        guard let udpFlow = flow as? NEAppProxyUDPFlow else { return false }
        udpFlow.readDatagrams { [weak self] datagrams, endpoints, error in
            guard let self else { return }
            if let error = error {
                os_log("UDP read error: %{public}@", log: .default, type: .error, error.localizedDescription)
                udpFlow.closeReadWithError(error)
                return
            }
            guard let packets = datagrams else { return }
            let eps = endpoints ?? []
            Task {
                await self.process(packets: packets, endpoints: eps, flow: udpFlow)
            }
        }
        return true
    }

    private func process(packets: [Data], endpoints: [NWEndpoint], flow: NEAppProxyUDPFlow) async {
        guard hasSubscriptionAccess() else {
            flow.closeReadWithError(DNSProxyError.subscriptionInactive)
            return
        }

        var forwardPackets: [Data] = []

        for packet in packets {
            guard let query = DNSMessage(data: packet) else { continue }
            if let qname = query.firstQuestionName(), isBlocked(domain: qname) {
                let response = query.blockedResponse()
                flow.writeDatagrams([response], sentBy: endpoints) { error in
                    if let error {
                        os_log("write blocked response failed: %{public}@", log: .default, type: .error, error.localizedDescription)
                    }
                }
            } else {
                forwardPackets.append(packet)
            }
        }

        if !forwardPackets.isEmpty {
            let upstream = NWHostEndpoint(hostname: upstreamPrimary, port: "53")
            flow.writeDatagrams(forwardPackets, sentBy: Array(repeating: upstream, count: forwardPackets.count)) { error in
                if let error {
                    os_log("forward write failed: %{public}@", log: .default, type: .error, error.localizedDescription)
                }
            }
        }

        flow.readDatagrams { [weak self] datagrams, endpoints, error in
            guard let self else { return }
            if let error = error {
                flow.closeReadWithError(error)
                return
            }
            if let datagrams = datagrams {
                let eps = endpoints ?? []
                flow.writeDatagrams(datagrams, sentBy: eps) { _ in }
            }
        }
    }

    private func isBlocked(domain: String) -> Bool {
        guard let normalized = normalize(domain) else { return false }
        return blocklist.contains(normalized) || blocklist.contains(where: { normalized.hasSuffix("." + $0) })
    }

    private func loadBlocklist() {
        guard let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else { return }
        let current = group.appendingPathComponent("Library/Application Support/Blocklists/blocklist.txt")
        let legacy = group.appendingPathComponent("blocklist.txt")
        guard let content = (try? String(contentsOf: current)) ?? (try? String(contentsOf: legacy)) else { return }
        blocklist = Set(content.components(separatedBy: .newlines).compactMap { normalize($0) })
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

    private func normalize(_ value: String) -> String? {
        let candidate = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
        guard !candidate.isEmpty, !candidate.contains("*"), !candidate.contains("/"), !candidate.contains("|") else {
            return nil
        }
        guard candidate.unicodeScalars.allSatisfy({ $0.value < 128 }) else { return nil }
        guard candidate.contains("."), !candidate.contains(":") else { return nil }
        let labels = candidate.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.allSatisfy({ label in
            guard !label.isEmpty, label.count <= 63,
                  label.first!.isLetter || label.first!.isNumber,
                  label.last!.isLetter || label.last!.isNumber else { return false }
            return label.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
        }) else { return nil }
        return candidate
    }
}

private struct SharedSubscriptionAccessSnapshot: Decodable {
    let isEntitled: Bool
    let effectiveUntil: Date?
}

private enum DNSProxyError: LocalizedError {
    case subscriptionInactive

    var errorDescription: String? {
        "Adless subscription is inactive"
    }
}

private extension DNSMessage {
    func firstQuestionName() -> String? {
        guard questions.count > 0 else { return nil }
        return questions[0].name
    }

    func blockedResponse() -> Data {
        var response = self
        response.header.flags = 0x8180 // standard response, recursion available
        response.answers = [DNSResourceRecord(name: firstQuestionName() ?? "", type: 1, cls: 1, ttl: 0, rdata: Data([0,0,0,0]))]
        return response.encode()
    }
}

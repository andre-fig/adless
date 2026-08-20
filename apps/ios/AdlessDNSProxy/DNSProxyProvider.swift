import NetworkExtension
import os.log

final class DNSProxyProvider: NEDNSProxyProvider {
    private var blocklist: Set<String> = []
    private let upstreamPrimary = "1.1.1.1"
    private let upstreamSecondary = "8.8.8.8"
    private let appGroupKey = "appGroup"

    override func startProxy(options: [String : Any]? = nil, completionHandler: @escaping (Error?) -> Void) {
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
        let normalized = domain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return blocklist.contains(normalized)
    }

    private func loadBlocklist() {
        let group = "group.com.adless.shared"
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?.appendingPathComponent("blocklist.txt"),
              let content = try? String(contentsOf: container) else { return }
        blocklist = Set(content.components(separatedBy: CharacterSet.newlines).filter { !$0.isEmpty })
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

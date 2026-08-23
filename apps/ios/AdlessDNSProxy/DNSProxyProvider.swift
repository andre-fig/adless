import Foundation
import Network
import NetworkExtension
import os

private let dnsLogger = Logger(subsystem: "com.orbeworks.adless", category: "dns-proxy")

final class DNSProxyProvider: NEDNSProxyProvider {
    private let upstreams = ["1.1.1.1", "8.8.8.8"]
    private let appGroupIdentifier = "group.com.orbeworks.adless"
    private let subscriptionStatePath = "Library/Application Support/Subscription/subscription-state.json"
    private let flowLock = NSLock()

    private var blocklist: Set<String> = []
    private var subscriptionState: SharedSubscriptionAccessSnapshot?
    private var subscriptionStateCheckedAt = Date.distantPast
    private var activeFlows: [ObjectIdentifier: DNSProxyFlowHandling] = [:]
    private let statsRecorder = BlockingStatsRecorder()

    override func startProxy(options: [String: Any]? = nil, completionHandler: @escaping (Error?) -> Void) {
        dnsLogger.info("DNS proxy start requested")
        if hasSubscriptionAccess() {
            loadBlocklist()
            dnsLogger.info("DNS proxy started with \(self.blocklist.count, privacy: .public) domains")
        } else {
            // Keep DNS forwarding available after entitlement expiry. An empty
            // blocklist makes the existing flow handlers pass every query to
            // the configured upstreams instead of discarding the flow.
            blocklist = []
            dnsLogger.info("DNS proxy started in pass-through mode: subscription inactive")
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
        // outage. Keep accepting supported flows and pass them through.
        let flowBlocklist = filteringEnabled ? blocklist : []

        let identifier = ObjectIdentifier(flow)
        if let udpFlow = flow as? NEAppProxyUDPFlow {
            dnsLogger.debug("New UDP DNS flow received; filtering enabled: \(filteringEnabled, privacy: .public)")
            let handler = DNSUDPFlowHandler(
                flow: udpFlow,
                blocklist: flowBlocklist,
                upstreams: upstreams,
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
                upstreams: upstreams,
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

    fileprivate static func normalize(_ value: String) -> String? {
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

private protocol DNSProxyFlowHandling: AnyObject {
    func start()
    func close(completion: @escaping () -> Void)
}

private struct DNSQueryKey: Hashable {
    let id: UInt16
    let name: String
}

private final class DNSUDPFlowHandler: DNSProxyFlowHandling, @unchecked Sendable {
    private enum PacketAction {
        case writeToClient(Data)
        case forward(Data, DNSQueryKey)
    }

    private struct PendingQuery {
        let packet: Data
        let clientEndpoint: Network.NWEndpoint
        var upstreamIndex: Int
        var fallbackSent = false
        var sent = false
    }

    private let flow: NEAppProxyUDPFlow
    private let blocklist: Set<String>
    private let upstreams: [Network.NWEndpoint]
    private let timeout: TimeInterval = 1.5
    private let queue = DispatchQueue(label: "com.orbeworks.adless.dns-udp", qos: .userInitiated)
    private let onClose: () -> Void
    private let onBlocked: () -> Void

    private var pending: [DNSQueryKey: PendingQuery] = [:]
    private var timeoutWorkItems: [DNSQueryKey: DispatchWorkItem] = [:]
    private var upstreamConnections: [NWConnection?] = []
    private var upstreamReady: [Bool] = []
    private var reconnectWorkItems: [DispatchWorkItem?] = []
    private var closed = false

    init(
        flow: NEAppProxyUDPFlow,
        blocklist: Set<String>,
        upstreams: [String],
        onClose: @escaping () -> Void,
        onBlocked: @escaping () -> Void
    ) {
        self.flow = flow
        self.blocklist = blocklist
        self.upstreams = upstreams.compactMap { host in
            guard let port = Network.NWEndpoint.Port(rawValue: 53) else { return nil }
            return .hostPort(host: Network.NWEndpoint.Host(host), port: port)
        }
        self.onClose = onClose
        self.onBlocked = onBlocked
    }

    func start() {
        flow.open(withLocalFlowEndpoint: nil) { [weak self] error in
            guard let self else { return }
            self.queue.async {
                guard error == nil else {
                    dnsLogger.error("UDP flow failed to open: \(error?.localizedDescription ?? "unknown error", privacy: .public)")
                    self.finish(error: error)
                    return
                }
                dnsLogger.debug("UDP flow opened; starting upstream connections")
                self.upstreamConnections = Array(repeating: nil, count: self.upstreams.count)
                self.upstreamReady = Array(repeating: false, count: self.upstreams.count)
                self.reconnectWorkItems = Array(repeating: nil, count: self.upstreams.count)
                for index in self.upstreams.indices {
                    self.connectUpstream(at: index)
                }
                self.readNext()
            }
        }
    }

    func close(completion: @escaping () -> Void) {
        queue.async { [self] in
            finish(error: nil, completion: completion)
        }
    }

    private func readNext() {
        guard !closed else { return }

        let flow = flow
        Task { [weak self] in
            let (datagrams, error) = await flow.readDatagrams()
            guard let self else { return }
            self.queue.async {
                guard !self.closed else { return }
                if let error {
                    dnsLogger.error("UDP flow read failed: \(error.localizedDescription, privacy: .public)")
                    self.finish(error: error)
                    return
                }

                guard let datagrams, !datagrams.isEmpty else {
                    self.finish(error: nil)
                    return
                }

                for (packet, endpoint) in datagrams {
                    switch self.process(packet: packet) {
                    case .writeToClient(let response):
                        self.writeToClient(packet: response, endpoint: endpoint)
                    case .forward(let request, let queryKey):
                        self.send(packet: request, to: endpoint, queryKey: queryKey)
                    }
                }
                self.readNext()
            }
        }
    }

    private func process(packet: Data) -> PacketAction {
        guard let message = DNSMessage(data: packet) else {
            return .forward(packet, DNSQueryKey(id: packet.dnsIdentifier, name: ""))
        }

        if message.isResponse {
            return .writeToClient(packet)
        }

        if let question = message.firstQuestionName(), isBlocked(domain: question) {
            onBlocked()
            return .writeToClient(message.blockedResponse())
        }

        return .forward(packet, queryKey(for: message))
    }

    private func connectUpstream(at index: Int) {
        guard !closed, upstreams.indices.contains(index) else { return }

        reconnectWorkItems[index]?.cancel()
        reconnectWorkItems[index] = nil
        upstreamConnections[index]?.cancel()

        let connection = NWConnection(to: upstreams[index], using: .udp)
        upstreamConnections[index] = connection
        upstreamReady[index] = false

        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection else { return }
            self.queue.async {
                guard !self.closed, self.upstreamConnections[index] === connection else { return }
                switch state {
                case .ready:
                    self.upstreamReady[index] = true
                    dnsLogger.info("UDP upstream \(index, privacy: .public) ready")
                    self.sendPendingQueries(to: index)
                case .failed(let error):
                    dnsLogger.error("UDP upstream \(index, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                    self.handleUpstreamFailure(connection, at: index, error: error)
                case .cancelled:
                    dnsLogger.error("UDP upstream \(index, privacy: .public) cancelled")
                    self.handleUpstreamFailure(connection, at: index, error: DNSProxyError.upstreamUnavailable)
                case .waiting(let error):
                    dnsLogger.warning("UDP upstream \(index, privacy: .public) waiting: \(error.localizedDescription, privacy: .public)")
                default:
                    break
                }
            }
        }

        connection.start(queue: queue)
        receiveFromUpstream(connection, at: index)
    }

    private func receiveFromUpstream(_ connection: NWConnection, at index: Int) {
        guard !closed, upstreamConnections.indices.contains(index), upstreamConnections[index] === connection else { return }

        connection.receiveMessage { [weak self, weak connection] data, _, _, error in
            guard let self, let connection else { return }
            self.queue.async {
                guard !self.closed, self.upstreamConnections[index] === connection else { return }
                if let data, !data.isEmpty {
                    self.handleUpstreamResponse(data)
                }

                if let error {
                    self.handleUpstreamFailure(connection, at: index, error: error)
                } else {
                    self.receiveFromUpstream(connection, at: index)
                }
            }
        }
    }

    private func send(packet: Data, to clientEndpoint: Network.NWEndpoint, queryKey: DNSQueryKey) {
        pending[queryKey] = PendingQuery(
            packet: packet,
            clientEndpoint: clientEndpoint,
            upstreamIndex: 0
        )
        scheduleFallback(for: queryKey)
        sendPendingQuery(queryKey)
    }

    private func sendPendingQueries(to upstreamIndex: Int) {
        let queryKeys = pending.keys.filter { pending[$0]?.upstreamIndex == upstreamIndex }
        for queryKey in queryKeys {
            sendPendingQuery(queryKey)
        }
    }

    private func sendPendingQuery(_ queryKey: DNSQueryKey) {
        guard var query = pending[queryKey], !query.sent else { return }
        let upstreamIndex = query.upstreamIndex
        guard upstreamReady.indices.contains(upstreamIndex),
              upstreamReady[upstreamIndex],
              let connection = upstreamConnections[upstreamIndex] else {
            return
        }

        query.sent = true
        pending[queryKey] = query
        dnsLogger.debug("DNS query sent to UDP upstream \(upstreamIndex, privacy: .public)")
        connection.send(content: query.packet, completion: .contentProcessed { [weak self, weak connection] error in
            guard let self, let connection else { return }
            self.queue.async {
                guard !self.closed,
                      self.upstreamConnections.indices.contains(upstreamIndex),
                      self.upstreamConnections[upstreamIndex] === connection,
                      let current = self.pending[queryKey],
                      current.upstreamIndex == upstreamIndex else { return }
                guard let error else { return }
                self.handleSendFailure(queryKey: queryKey, upstreamIndex: upstreamIndex, error: error)
            }
        })
    }

    private func handleSendFailure(queryKey: DNSQueryKey, upstreamIndex: Int, error: Error) {
        guard upstreamIndex == 0 else {
            respondWithServerFailure(queryKey)
            dnsLogger.error("DNS secondary upstream send failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        fallback(queryKey: queryKey, reason: error)
    }

    private func scheduleFallback(for queryKey: DNSQueryKey) {
        let workItem = DispatchWorkItem { [weak self] in
            self?.fallback(queryKey: queryKey, reason: nil)
        }
        timeoutWorkItems[queryKey] = workItem
        queue.asyncAfter(deadline: .now() + timeout, execute: workItem)
    }

    private func fallback(queryKey: DNSQueryKey, reason: Error?) {
        guard var query = pending[queryKey], !query.fallbackSent else {
            return
        }

        guard upstreams.count > 1 else {
            if let reason {
                dnsLogger.error("DNS primary upstream failed with no secondary: \(reason.localizedDescription, privacy: .public)")
            }
            respondWithServerFailure(queryKey)
            return
        }

        query.fallbackSent = true
        query.upstreamIndex = 1
        query.sent = false
        pending[queryKey] = query
        timeoutWorkItems.removeValue(forKey: queryKey)?.cancel()
        dnsLogger.info("DNS primary upstream timed out; trying secondary")

        let expiry = DispatchWorkItem { [weak self] in
            self?.respondWithServerFailure(queryKey)
        }
        timeoutWorkItems[queryKey] = expiry
        queue.asyncAfter(deadline: .now() + timeout, execute: expiry)
        sendPendingQuery(queryKey)
    }

    private func handleUpstreamFailure(_ connection: NWConnection, at index: Int, error: Error) {
        guard upstreamConnections.indices.contains(index), upstreamConnections[index] === connection else { return }
        upstreamConnections[index] = nil
        upstreamReady[index] = false
        connection.cancel()

        let affectedQueries = pending.compactMap { key, query in
            query.upstreamIndex == index ? key : nil
        }
        for queryKey in affectedQueries {
            if index == 0 {
                fallback(queryKey: queryKey, reason: error)
            } else {
                respondWithServerFailure(queryKey)
            }
        }

        scheduleReconnect(for: index)
    }

    private func scheduleReconnect(for index: Int) {
        guard !closed, reconnectWorkItems.indices.contains(index) else { return }
        reconnectWorkItems[index]?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.connectUpstream(at: index)
        }
        reconnectWorkItems[index] = workItem
        queue.asyncAfter(deadline: .now() + timeout, execute: workItem)
    }

    private func handleUpstreamResponse(_ packet: Data) {
        guard let queryKey = pendingKey(for: packet),
              let query = pending.removeValue(forKey: queryKey) else { return }
        timeoutWorkItems.removeValue(forKey: queryKey)?.cancel()
        writeToClient(packet: packet, endpoint: query.clientEndpoint)
    }

    private func pendingKey(for packet: Data) -> DNSQueryKey? {
        if let message = DNSMessage(data: packet) {
            let key = queryKey(for: message)
            if pending[key] != nil { return key }
        }

        let identifier = packet.dnsIdentifier
        return pending.keys.first { $0.id == identifier }
    }

    private func writeToClient(packet: Data, endpoint: Network.NWEndpoint) {
        // The proxy flow writes responses back to the app. Upstream DNS traffic
        // is sent through NWConnection, because this endpoint is the response
        // source endpoint for the proxied UDP conversation.
        let flow = flow
        Task { [weak self] in
            do {
                try await flow.writeDatagrams([(packet, endpoint)])
            } catch {
                guard let self else { return }
                self.queue.async {
                    guard !self.closed else { return }
                    dnsLogger.error("DNS response write failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    private func respondWithServerFailure(_ queryKey: DNSQueryKey) {
        guard let query = pending.removeValue(forKey: queryKey) else { return }
        timeoutWorkItems.removeValue(forKey: queryKey)?.cancel()

        let response = DNSMessage(data: query.packet)?.serverFailureResponse()
            ?? DNSMessage.serverFailureResponse(id: query.packet.dnsIdentifier)
        dnsLogger.error("DNS query failed on all upstreams; returning SERVFAIL")
        writeToClient(packet: response, endpoint: query.clientEndpoint)
    }

    private func isBlocked(domain: String) -> Bool {
        guard let normalized = DNSProxyProvider.normalize(domain) else { return false }
        let labels = normalized.split(separator: ".")
        for index in labels.indices {
            if blocklist.contains(labels[index...].joined(separator: ".")) {
                return true
            }
        }
        return false
    }

    private func queryKey(for message: DNSMessage) -> DNSQueryKey {
        guard let name = message.firstQuestionName(),
              let normalized = DNSProxyProvider.normalize(name) else {
            return DNSQueryKey(id: message.header.id, name: "")
        }
        return DNSQueryKey(id: message.header.id, name: normalized)
    }

    private func finish(error: Error?, completion: (() -> Void)? = nil) {
        guard !closed else {
            completion?()
            return
        }
        closed = true
        timeoutWorkItems.values.forEach { $0.cancel() }
        timeoutWorkItems.removeAll()
        reconnectWorkItems.forEach { $0?.cancel() }
        reconnectWorkItems.removeAll()
        upstreamConnections.forEach { $0?.cancel() }
        upstreamConnections.removeAll()
        pending.removeAll()
        if let error {
            dnsLogger.error("DNS UDP flow closed: \(error.localizedDescription, privacy: .public)")
        }
        flow.closeReadWithError(error as NSError?)
        flow.closeWriteWithError(error as NSError?)
        onClose()
        completion?()
    }
}

private final class DNSTCPFlowHandler: DNSProxyFlowHandling {
    private let flow: NEAppProxyTCPFlow
    private let blocklist: Set<String>
    private let upstreams: [String]
    private let queue = DispatchQueue(label: "com.orbeworks.adless.dns-tcp", qos: .userInitiated)
    private let onClose: () -> Void
    private let onBlocked: () -> Void
    private let connectionTimeout: TimeInterval = 1.5
    private let maximumPendingBytes = 256 * 1024

    private var clientBuffer = Data()
    private var pendingUpstreamFrames: [Data] = []
    private var pendingUpstreamBytes = 0
    private var connection: NWConnection?
    private var connectionTimeoutWorkItem: DispatchWorkItem?
    private var connectionAttempt: Int?
    private var isConnectionReady = false
    private var closed = false

    init(
        flow: NEAppProxyTCPFlow,
        blocklist: Set<String>,
        upstreams: [String],
        onClose: @escaping () -> Void,
        onBlocked: @escaping () -> Void
    ) {
        self.flow = flow
        self.blocklist = blocklist
        self.upstreams = upstreams
        self.onClose = onClose
        self.onBlocked = onBlocked
    }

    func start() {
        flow.open(withLocalFlowEndpoint: nil) { [weak self] error in
            guard let self else { return }
            self.queue.async {
                guard error == nil else {
                    self.finish(error: error)
                    return
                }
                self.readFromClient()
                self.connectToUpstream(attempt: 0)
            }
        }
    }

    func close(completion: @escaping () -> Void) {
        queue.async { [self] in
            finish(error: nil, completion: completion)
        }
    }

    private func readFromClient() {
        guard !closed else { return }

        flow.readData { [weak self] data, error in
            guard let self else { return }
            self.queue.async {
                guard !self.closed else { return }
                if let error {
                    self.finish(error: error)
                    return
                }
                guard let data, !data.isEmpty else {
                    self.finish(error: nil)
                    return
                }

                self.clientBuffer.append(data)
                self.processClientBuffer()
                self.readFromClient()
            }
        }
    }

    private func processClientBuffer() {
        while clientBuffer.count >= 2 {
            let length = Int(clientBuffer[clientBuffer.startIndex]) * 256
                + Int(clientBuffer[clientBuffer.startIndex + 1])
            guard length > 0 else {
                finish(error: DNSProxyError.invalidTCPDNSMessage)
                return
            }

            let frameLength = length + 2
            guard clientBuffer.count >= frameLength else { return }

            let packet = clientBuffer.subdata(in: 2..<frameLength)
            clientBuffer.removeSubrange(0..<frameLength)
            let framedPacket = frame(packet)

            if let message = DNSMessage(data: packet),
               let question = message.firstQuestionName(),
               isBlocked(domain: question) {
                onBlocked()
                writeToClient(framedPacket: frame(message.blockedResponse()))
            } else {
                guard pendingUpstreamBytes + framedPacket.count <= maximumPendingBytes else {
                    finish(error: DNSProxyError.upstreamBacklogExceeded)
                    return
                }
                pendingUpstreamFrames.append(framedPacket)
                pendingUpstreamBytes += framedPacket.count
            }
        }

        flushPendingUpstreamFrames()
    }

    private func connectToUpstream(attempt: Int) {
        guard !closed else { return }
        guard attempt < upstreams.count else {
            finish(error: DNSProxyError.upstreamUnavailable)
            return
        }
        guard let port = Network.NWEndpoint.Port(rawValue: 53) else {
            finish(error: DNSProxyError.upstreamUnavailable)
            return
        }

        let connection = NWConnection(host: Network.NWEndpoint.Host(upstreams[attempt]), port: port, using: .tcp)
        self.connection = connection
        self.connectionAttempt = attempt
        self.isConnectionReady = false

        let timeoutWorkItem = DispatchWorkItem { [weak self, weak connection] in
            guard let self, let connection else { return }
            self.handleUpstreamFailure(connection, attempt: attempt, error: DNSProxyError.upstreamTimeout)
        }
        connectionTimeoutWorkItem = timeoutWorkItem
        queue.asyncAfter(deadline: .now() + connectionTimeout, execute: timeoutWorkItem)

        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection else { return }
            self.queue.async {
                guard self.connection === connection, self.connectionAttempt == attempt else { return }
                switch state {
                case .ready:
                    self.connectionTimeoutWorkItem?.cancel()
                    self.connectionTimeoutWorkItem = nil
                    self.isConnectionReady = true
                    self.flushPendingUpstreamFrames()
                    self.readFromUpstream(connection)
                case .failed(let error):
                    self.handleUpstreamFailure(connection, attempt: attempt, error: error)
                case .cancelled:
                    self.handleUpstreamFailure(connection, attempt: attempt, error: DNSProxyError.upstreamUnavailable)
                default:
                    break
                }
            }
        }
        connection.start(queue: queue)
    }

    private func handleUpstreamFailure(_ connection: NWConnection, attempt: Int, error: Error) {
        guard self.connection === connection, connectionAttempt == attempt else { return }
        let wasReady = isConnectionReady
        self.connection = nil
        connectionAttempt = nil
        isConnectionReady = false
        connectionTimeoutWorkItem?.cancel()
        connectionTimeoutWorkItem = nil
        connection.cancel()

        guard !wasReady, attempt + 1 < upstreams.count else {
            finish(error: error)
            return
        }

        dnsLogger.info("DNS TCP upstream failed; trying secondary")
        connectToUpstream(attempt: attempt + 1)
    }

    private func flushPendingUpstreamFrames() {
        guard isConnectionReady, let connection else { return }

        while !pendingUpstreamFrames.isEmpty {
            let packet = pendingUpstreamFrames.removeFirst()
            pendingUpstreamBytes -= packet.count
            connection.send(content: packet, completion: .contentProcessed { [weak self, weak connection] error in
                guard let self, let connection else { return }
                guard let error else { return }
                self.queue.async {
                    self.handleUpstreamFailure(connection, attempt: self.connectionAttempt ?? 0, error: error)
                }
            })
        }
    }

    private func readFromUpstream(_ connection: NWConnection) {
        guard !closed, self.connection === connection else { return }

        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self, weak connection] data, _, isComplete, error in
            guard let self, let connection else { return }
            self.queue.async {
                guard !self.closed, self.connection === connection else { return }
                if let data, !data.isEmpty {
                    self.writeToClient(data: data)
                }
                if let error {
                    self.handleUpstreamFailure(connection, attempt: self.connectionAttempt ?? 0, error: error)
                } else if isComplete {
                    self.finish(error: nil)
                } else {
                    self.readFromUpstream(connection)
                }
            }
        }
    }

    private func writeToClient(framedPacket: Data) {
        writeToClient(data: framedPacket)
    }

    private func writeToClient(data: Data) {
        flow.write(data) { [weak self] error in
            guard let self, let error else { return }
            self.queue.async {
                self.finish(error: error)
            }
        }
    }

    private func isBlocked(domain: String) -> Bool {
        guard let normalized = DNSProxyProvider.normalize(domain) else { return false }
        let labels = normalized.split(separator: ".")
        for index in labels.indices {
            if blocklist.contains(labels[index...].joined(separator: ".")) {
                return true
            }
        }
        return false
    }

    private func frame(_ packet: Data) -> Data {
        var result = Data([UInt8(packet.count >> 8), UInt8(packet.count & 0xff)])
        result.append(packet)
        return result
    }

    private func finish(error: Error?, completion: (() -> Void)? = nil) {
        guard !closed else {
            completion?()
            return
        }
        closed = true
        connectionTimeoutWorkItem?.cancel()
        connectionTimeoutWorkItem = nil
        connectionAttempt = nil
        connection?.cancel()
        connection = nil
        if let error {
            dnsLogger.error("DNS TCP flow closed: \(error.localizedDescription, privacy: .public)")
        }
        flow.closeReadWithError(error as NSError?)
        flow.closeWriteWithError(error as NSError?)
        onClose()
        completion?()
    }
}

private struct SharedSubscriptionAccessSnapshot: Decodable {
    let isEntitled: Bool
    let effectiveUntil: Date?
}

private enum DNSProxyError: LocalizedError {
    case invalidTCPDNSMessage
    case upstreamTimeout
    case upstreamUnavailable
    case upstreamBacklogExceeded

    var errorDescription: String? {
        switch self {
        case .invalidTCPDNSMessage:
            return "Invalid DNS over TCP message"
        case .upstreamTimeout:
            return "DNS upstream timed out"
        case .upstreamUnavailable:
            return "DNS upstream unavailable"
        case .upstreamBacklogExceeded:
            return "DNS upstream backlog exceeded"
        }
    }
}

private extension DNSMessage {
    var isResponse: Bool {
        header.flags & 0x8000 != 0
    }

    func firstQuestionName() -> String? {
        guard !questions.isEmpty else { return nil }
        return questions[0].name
    }

    func blockedResponse() -> Data {
        var response = self
        response.header.flags = 0x8180
        response.answers = [DNSResourceRecord(
            name: firstQuestionName() ?? "",
            type: 1,
            cls: 1,
            ttl: 0,
            rdata: Data([0, 0, 0, 0])
        )]
        return response.encode()
    }
}

private extension Data {
    var dnsIdentifier: UInt16 {
        guard count >= 2 else { return 0 }
        return (UInt16(self[startIndex]) << 8) | UInt16(self[index(startIndex, offsetBy: 1)])
    }
}

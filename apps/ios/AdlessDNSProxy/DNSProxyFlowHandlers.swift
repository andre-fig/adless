import Foundation
import Network
import NetworkExtension
import os

private let dnsFlowLogger = Logger(subsystem: "com.orbeworks.adless", category: "dns-flow")

protocol DNSProxyFlowHandling: AnyObject {
    func start()
    func close(completion: @escaping () -> Void)
}

enum DNSProxyError: LocalizedError {
    case invalidDNSMessage
    case invalidTCPDNSMessage
    case upstreamBacklogExceeded

    var errorDescription: String? {
        switch self {
        case .invalidDNSMessage:
            return "Invalid DNS message"
        case .invalidTCPDNSMessage:
            return "Invalid DNS over TCP message"
        case .upstreamBacklogExceeded:
            return "DNS upstream backlog exceeded"
        }
    }
}

final class DNSUDPFlowHandler: DNSProxyFlowHandling, @unchecked Sendable {
    private let flow: NEAppProxyUDPFlow
    private let blocklist: Set<String>
    private let resolver: DNSUpstreamResolver
    private let queue = DispatchQueue(label: "com.orbeworks.adless.dns-udp", qos: .userInitiated)
    private let onClose: () -> Void
    private let onBlocked: () -> Void

    private var readTask: Task<Void, Never>?
    private var resolveTasks: [UUID: Task<Void, Never>] = [:]
    private var closed = false

    init(
        flow: NEAppProxyUDPFlow,
        blocklist: Set<String>,
        resolver: DNSUpstreamResolver,
        onClose: @escaping () -> Void,
        onBlocked: @escaping () -> Void
    ) {
        self.flow = flow
        self.blocklist = blocklist
        self.resolver = resolver
        self.onClose = onClose
        self.onBlocked = onBlocked
    }

    func start() {
        flow.open(withLocalFlowEndpoint: nil) { [weak self] error in
            guard let self else { return }
            self.queue.async {
                guard error == nil else {
                    dnsFlowLogger.error("UDP flow failed to open: \(error?.localizedDescription ?? "unknown error", privacy: .public)")
                    self.finish(error: error)
                    return
                }
                dnsFlowLogger.debug("UDP flow opened with encrypted DNS upstream")
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
        readTask = Task { [weak self] in
            let (datagrams, error) = await flow.readDatagrams()
            guard let self else { return }
            self.queue.async {
                guard !self.closed else { return }
                if let error {
                    dnsFlowLogger.error("UDP flow read failed: \(error.localizedDescription, privacy: .public)")
                    self.finish(error: error)
                    return
                }

                guard let datagrams, !datagrams.isEmpty else {
                    self.finish(error: nil)
                    return
                }

                for (packet, endpoint) in datagrams {
                    self.process(packet: packet, endpoint: endpoint)
                }
                self.readNext()
            }
        }
    }

    private func process(packet: Data, endpoint: Network.NWEndpoint) {
        guard let message = DNSMessage(data: packet) else {
            writeToClient(packet: DNSMessage.serverFailureResponse(id: packet.dnsIdentifier), endpoint: endpoint)
            return
        }

        if message.isResponse {
            writeToClient(packet: packet, endpoint: endpoint)
            return
        }

        if let bootstrapResponse = DNSDoHEndpoint.bootstrapResponse(for: packet) {
            writeToClient(packet: bootstrapResponse, endpoint: endpoint)
            return
        }

        if let question = message.firstQuestionName(), isBlocked(domain: question) {
            onBlocked()
            writeToClient(packet: message.blockedResponse(), endpoint: endpoint)
            return
        }

        resolve(packet: packet, failureResponse: message.serverFailureResponse(), endpoint: endpoint)
    }

    private func resolve(packet: Data, failureResponse: Data, endpoint: Network.NWEndpoint) {
        let requestID = UUID()
        let resolver = resolver
        let task = Task { [weak self] in
            do {
                let response = try await resolver.resolve(packet)
                guard !Task.isCancelled else { return }
                self?.queue.async {
                    self?.complete(requestID: requestID, packet: response, endpoint: endpoint)
                }
            } catch is CancellationError {
                return
            } catch {
                self?.queue.async {
                    self?.complete(requestID: requestID, packet: failureResponse, endpoint: endpoint)
                }
            }
        }
        resolveTasks[requestID] = task
    }

    private func complete(requestID: UUID, packet: Data, endpoint: Network.NWEndpoint) {
        resolveTasks.removeValue(forKey: requestID)
        guard !closed else { return }
        writeToClient(packet: packet, endpoint: endpoint)
    }

    private func writeToClient(packet: Data, endpoint: Network.NWEndpoint) {
        guard !closed else { return }
        let flow = flow
        Task { [weak self] in
            do {
                try await flow.writeDatagrams([(packet, endpoint)])
            } catch {
                guard let self else { return }
                self.queue.async {
                    guard !self.closed else { return }
                    dnsFlowLogger.error("UDP response write failed: \(error.localizedDescription, privacy: .public)")
                }
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

    private func finish(error: Error?, completion: (() -> Void)? = nil) {
        guard !closed else {
            completion?()
            return
        }
        closed = true
        readTask?.cancel()
        readTask = nil
        resolveTasks.values.forEach { $0.cancel() }
        resolveTasks.removeAll()
        if let error {
            dnsFlowLogger.error("UDP flow closed: \(error.localizedDescription, privacy: .public)")
        }
        flow.closeReadWithError(error as NSError?)
        flow.closeWriteWithError(error as NSError?)
        onClose()
        completion?()
    }
}

final class DNSTCPFlowHandler: DNSProxyFlowHandling, @unchecked Sendable {
    private let flow: NEAppProxyTCPFlow
    private let blocklist: Set<String>
    private let resolver: DNSUpstreamResolver
    private let queue = DispatchQueue(label: "com.orbeworks.adless.dns-tcp", qos: .userInitiated)
    private let onClose: () -> Void
    private let onBlocked: () -> Void
    private let maximumPendingBytes = 256 * 1024
    private let maximumPendingRequests = 256

    private var clientBuffer = Data()
    private var pendingResponseBytes = 0
    private var pendingWrites: [Data] = []
    private var isWriting = false
    private var resolveTasks: [UUID: Task<Void, Never>] = [:]
    private var closed = false

    init(
        flow: NEAppProxyTCPFlow,
        blocklist: Set<String>,
        resolver: DNSUpstreamResolver,
        onClose: @escaping () -> Void,
        onBlocked: @escaping () -> Void
    ) {
        self.flow = flow
        self.blocklist = blocklist
        self.resolver = resolver
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
                if self.clientBuffer.count > self.maximumPendingBytes {
                    self.finish(error: DNSProxyError.upstreamBacklogExceeded)
                    return
                }
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

            guard let message = DNSMessage(data: packet) else {
                enqueueWrite(frame(DNSMessage.serverFailureResponse(id: packet.dnsIdentifier)))
                continue
            }

            if message.isResponse {
                enqueueWrite(frame(packet))
            } else if let bootstrapResponse = DNSDoHEndpoint.bootstrapResponse(for: packet) {
                enqueueWrite(frame(bootstrapResponse))
            } else if let question = message.firstQuestionName(), isBlocked(domain: question) {
                onBlocked()
                enqueueWrite(frame(message.blockedResponse()))
            } else if resolveTasks.count >= maximumPendingRequests {
                finish(error: DNSProxyError.upstreamBacklogExceeded)
                return
            } else {
                resolve(
                    packet: packet,
                    failureResponse: message.serverFailureResponse(),
                    requestID: UUID()
                )
            }
        }
    }

    private func resolve(packet: Data, failureResponse: Data, requestID: UUID) {
        let resolver = resolver
        let task = Task { [weak self] in
            do {
                let response = try await resolver.resolve(packet)
                guard !Task.isCancelled else { return }
                self?.queue.async {
                    self?.complete(requestID: requestID, response: response)
                }
            } catch is CancellationError {
                return
            } catch {
                self?.queue.async {
                    self?.complete(requestID: requestID, response: failureResponse)
                }
            }
        }
        resolveTasks[requestID] = task
    }

    private func complete(requestID: UUID, response: Data) {
        resolveTasks.removeValue(forKey: requestID)
        guard !closed else { return }
        enqueueWrite(frame(response))
    }

    private func enqueueWrite(_ data: Data) {
        guard !closed else { return }
        guard pendingResponseBytes + data.count <= maximumPendingBytes else {
            finish(error: DNSProxyError.upstreamBacklogExceeded)
            return
        }
        pendingWrites.append(data)
        pendingResponseBytes += data.count
        flushWrites()
    }

    private func flushWrites() {
        guard !closed, !isWriting, let data = pendingWrites.first else { return }
        isWriting = true
        flow.write(data) { [weak self] error in
            guard let self else { return }
            self.queue.async {
                guard !self.closed else { return }
                self.isWriting = false
                self.pendingWrites.removeFirst()
                self.pendingResponseBytes -= data.count
                if let error {
                    self.finish(error: error)
                } else {
                    self.flushWrites()
                }
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
        guard packet.count <= UInt16.max else {
            return Data([0, 0])
        }
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
        resolveTasks.values.forEach { $0.cancel() }
        resolveTasks.removeAll()
        pendingWrites.removeAll()
        pendingResponseBytes = 0
        if let error {
            dnsFlowLogger.error("TCP flow closed: \(error.localizedDescription, privacy: .public)")
        }
        flow.closeReadWithError(error as NSError?)
        flow.closeWriteWithError(error as NSError?)
        onClose()
        completion?()
    }
}

extension DNSMessage {
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

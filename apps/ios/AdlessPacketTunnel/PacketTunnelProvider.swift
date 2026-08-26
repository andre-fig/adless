import Darwin
import Foundation
import NetworkExtension

final class PacketTunnelProvider: NEPacketTunnelProvider, @unchecked Sendable {
    private static let maximumUDPResponseBytes = 1_232
    private static let maximumTCPPayloadBytes = Int(UInt16.max) - 20 - 20
    private static let dnsIPv4 = "10.255.255.2"
    private static let tunnelIPv4 = "10.255.255.1"
    private static let tunnelRemoteIPv4 = "10.255.255.254"
    private static let dnsIPv6 = "fd00:ad1e:55::53"
    private static let tunnelIPv6 = "fd00:ad1e:55::1"

    private let packetQueue = DispatchQueue(
        label: "com.orbeworks.adless.packet-tunnel",
        qos: .userInitiated
    )
    private let dnsService = PacketTunnelDNSService()
    private let subscriptionAccess = PacketTunnelSubscriptionAccess()
    private let statsRecorder = BlockingStatsRecorder()

    private var blocklist: Set<String> = []
    private var filteringEnabled = false
    private var lastPolicyRefresh = Date.distantPast
    private var isStopping = false
    private var udpTasks: [UUID: Task<Void, Never>] = [:]
    private var tcpTasks: [UUID: Task<Void, Never>] = [:]
    private var tcpConnections: [TCPConnectionKey: TCPConnection] = [:]

    override func startTunnel(
        options: [String: NSObject]?,
        completionHandler: @escaping (Error?) -> Void
    ) {
        PacketTunnelTelemetry.start()
        PacketTunnelTelemetry.event("tunnel.start")
        packetQueue.async { [weak self] in
            guard let self else { return }
            self.isStopping = false
            self.loadBlocklist(operation: "blocklist.load")
            self.refreshPolicy()

            let settings = self.makeNetworkSettings()
            PacketTunnelTelemetry.event("tunnel.settings")
            self.setTunnelNetworkSettings(settings) { [weak self] error in
                guard let self else { return }
                self.packetQueue.async {
                    if let error {
                        PacketTunnelTelemetry.error(error, operation: "tunnel.error")
                        completionHandler(error)
                        return
                    }
                    self.readNextPacket()
                    PacketTunnelTelemetry.event("tunnel.start", status: .connected)
                    completionHandler(nil)
                }
            }
        }
    }

    override func stopTunnel(
        with reason: NEProviderStopReason,
        completionHandler: @escaping () -> Void
    ) {
        packetQueue.async { [weak self] in
            guard let self else {
                completionHandler()
                return
            }
            self.isStopping = true
            self.udpTasks.values.forEach { $0.cancel() }
            self.udpTasks.removeAll()
            self.tcpTasks.values.forEach { $0.cancel() }
            self.tcpTasks.removeAll()
            self.tcpConnections.removeAll()
            self.statsRecorder.flush()
            PacketTunnelTelemetry.event("tunnel.stop")
            completionHandler()
        }
    }

    override func handleAppMessage(
        _ messageData: Data,
        completionHandler: ((Data?) -> Void)? = nil
    ) {
        guard String(data: messageData, encoding: .utf8) == "reloadBlocklist" else {
            completionHandler?(nil)
            return
        }

        packetQueue.async { [weak self] in
            guard let self else {
                completionHandler?(nil)
                return
            }
            self.loadBlocklist(operation: "blocklist.reload")
            self.refreshPolicy()
            completionHandler?(Data("ok".utf8))
        }
    }

    private func makeNetworkSettings() -> NEPacketTunnelNetworkSettings {
        // NetworkExtension requires a remote address for the virtual
        // interface. This RFC1918 value is only a local peer marker; it is
        // never contacted and is not an Adless VPN server.
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: Self.tunnelRemoteIPv4)
        settings.mtu = 1_500

        let ipv4 = NEIPv4Settings(
            addresses: [Self.tunnelIPv4],
            subnetMasks: ["255.255.255.0"]
        )
        // Only the synthetic DNS address is routed into the tunnel. There is
        // deliberately no default route, so application traffic and the DoH
        // HTTPS connection stay on the underlying network path.
        ipv4.includedRoutes = [
            NEIPv4Route(destinationAddress: Self.dnsIPv4, subnetMask: "255.255.255.255")
        ]
        settings.ipv4Settings = ipv4

        let ipv6 = NEIPv6Settings(
            addresses: [Self.tunnelIPv6],
            networkPrefixLengths: [64]
        )
        ipv6.includedRoutes = [
            NEIPv6Route(destinationAddress: Self.dnsIPv6, networkPrefixLength: 128)
        ]
        settings.ipv6Settings = ipv6

        let dns = NEDNSSettings(servers: [Self.dnsIPv4, Self.dnsIPv6])
        dns.matchDomains = [""]
        dns.matchDomainsNoSearch = true
        settings.dnsSettings = dns
        return settings
    }

    private func readNextPacket() {
        guard !isStopping else { return }
        packetFlow.readPackets { [weak self] packets, _ in
            guard let self else { return }
            self.packetQueue.async {
                guard !self.isStopping else { return }
                for packet in packets {
                    self.handle(packet: packet)
                }
                self.readNextPacket()
            }
        }
    }

    private func handle(packet data: Data) {
        refreshPolicyIfNeeded()
        guard let packet = DNSPacket(data: data), packet.destinationPort == 53 else {
            // Split routing means non-DNS packets normally never arrive here.
            // If the system supplies one anyway, it is intentionally ignored;
            // Adless does not inspect or forward application payloads.
            return
        }

        if packet.transport == .udp {
            handleUDP(packet)
        } else {
            handleTCP(packet)
        }
    }

    private func handleUDP(_ packet: DNSPacket) {
        let requestID = UUID()
        let service = dnsService
        let task = Task { [weak self] in
            let result = await service.resolve(packet.payload)
            guard let self else { return }
            self.packetQueue.async {
                self.udpTasks.removeValue(forKey: requestID)
                guard !self.isStopping else { return }
                if result.wasBlocked {
                    self.statsRecorder.recordBlockedRequest()
                }
                let responsePayload = Self.udpResponsePayload(result.response)
                guard let response = DNSPacketWriter.udpResponse(for: packet, payload: responsePayload) else {
                    return
                }
                self.write(response, version: packet.version)
            }
        }
        udpTasks[requestID] = task
    }

    private func handleTCP(_ packet: DNSPacket) {
        guard let sequence = packet.tcpSequenceNumber,
              let acknowledgment = packet.tcpAcknowledgmentNumber else { return }

        let key = TCPConnectionKey(packet: packet)
        let syn = packet.tcpFlags & TCPFlags.syn != 0
        let ack = packet.tcpFlags & TCPFlags.ack != 0
        let fin = packet.tcpFlags & TCPFlags.fin != 0
        let rst = packet.tcpFlags & TCPFlags.rst != 0

        if rst {
            removeTCPConnection(key)
            return
        }

        if tcpConnections[key] == nil, syn {
            removeExpiredTCPConnections()
            guard tcpConnections.count < 256 else { return }
            let serverInitial = UInt32.random(in: UInt32.min...UInt32.max)
            let connection = TCPConnection(
                template: packet,
                clientNextSequence: sequence &+ 1,
                serverNextSequence: serverInitial &+ 1,
                established: false
            )
            tcpConnections[key] = connection
            writeTCP(
                packet: packet,
                sequence: serverInitial,
                acknowledgment: sequence &+ 1,
                flags: TCPFlags.syn | TCPFlags.ack
            )
            return
        }

        guard var connection = tcpConnections[key] else { return }
        connection.template = packet
        connection.lastActivity = Date()

        if !connection.established {
            if syn {
                // Retransmitted SYNs must receive the same SYN-ACK while the
                // client is waiting for the first handshake response.
                tcpConnections[key] = connection
                writeTCP(
                    packet: packet,
                    sequence: connection.serverNextSequence &- 1,
                    acknowledgment: sequence &+ 1,
                    flags: TCPFlags.syn | TCPFlags.ack
                )
                return
            }
            guard ack, acknowledgment == connection.serverNextSequence else {
                tcpConnections[key] = connection
                return
            }
            connection.established = true
        }

        if sequence != connection.clientNextSequence, !packet.payload.isEmpty {
            // A duplicate or out-of-order segment is answered with the current
            // ACK. The extension does not implement a second TCP stack.
            tcpConnections[key] = connection
            writeTCP(
                packet: packet,
                sequence: connection.serverNextSequence,
                acknowledgment: connection.clientNextSequence,
                flags: TCPFlags.ack
            )
            return
        }

        if !packet.payload.isEmpty {
            connection.clientNextSequence &+= UInt32(packet.payload.count)
            connection.inputBuffer.append(packet.payload)
            tcpConnections[key] = connection
            writeTCP(
                packet: packet,
                sequence: connection.serverNextSequence,
                acknowledgment: connection.clientNextSequence,
                flags: TCPFlags.ack
            )
            parseTCPFrames(for: key)
        }

        if fin {
            connection.clientNextSequence &+= 1
            tcpConnections[key] = connection
            writeTCP(
                packet: packet,
                sequence: connection.serverNextSequence,
                acknowledgment: connection.clientNextSequence,
                flags: TCPFlags.ack
            )
            removeTCPConnection(key)
        } else {
            tcpConnections[key] = connection
        }

        removeExpiredTCPConnections()
    }

    private func parseTCPFrames(for key: TCPConnectionKey) {
        guard var connection = tcpConnections[key] else { return }
        let maximumBuffer = 256 * 1024
        guard connection.inputBuffer.count <= maximumBuffer else {
            removeTCPConnection(key)
            return
        }

        while connection.inputBuffer.count >= 2 {
            let length = Int(connection.inputBuffer[0]) << 8 | Int(connection.inputBuffer[1])
            guard length > 0 else {
                removeTCPConnection(key)
                return
            }
            let frameLength = length + 2
            guard connection.inputBuffer.count >= frameLength else { break }
            let query = connection.inputBuffer.subdata(in: 2..<frameLength)
            connection.inputBuffer.removeSubrange(0..<frameLength)

            guard connection.pendingOrder.count < 256 else {
                removeTCPConnection(key)
                return
            }
            let requestID = UUID()
            connection.pendingOrder.append(requestID)
            let service = dnsService
            let task = Task { [weak self] in
                let result = await service.resolve(query)
                guard let self else { return }
                self.packetQueue.async {
                    self.tcpTasks.removeValue(forKey: requestID)
                    guard var current = self.tcpConnections[key], !self.isStopping else { return }
                    current.completed[requestID] = result
                    self.tcpConnections[key] = current
                    self.drainTCPResponses(for: key)
                }
            }
            tcpTasks[requestID] = task
        }
        tcpConnections[key] = connection
    }

    private func drainTCPResponses(for key: TCPConnectionKey) {
        guard var connection = tcpConnections[key] else { return }
        while let requestID = connection.pendingOrder.first,
              let result = connection.completed.removeValue(forKey: requestID) {
            connection.pendingOrder.removeFirst()
            let framed = Data([UInt8(result.response.count >> 8), UInt8(result.response.count & 0xff)]) + result.response
            var offset = 0
            var sequenceNumber = connection.serverNextSequence
            while offset < framed.count {
                let chunkLength = min(Self.maximumTCPPayloadBytes, framed.count - offset)
                let chunk = framed.subdata(in: offset..<(offset + chunkLength))
                let isLastChunk = offset + chunkLength == framed.count
                guard let response = DNSPacketWriter.tcpResponse(
                    for: connection.template,
                    sequenceNumber: sequenceNumber,
                    acknowledgmentNumber: connection.clientNextSequence,
                    flags: (isLastChunk ? TCPFlags.psh : 0) | TCPFlags.ack,
                    payload: chunk
                ) else {
                    removeTCPConnection(key)
                    return
                }
                write(response, version: connection.template.version)
                offset += chunkLength
                sequenceNumber &+= UInt32(chunkLength)
            }
            connection.serverNextSequence = sequenceNumber
            if result.wasBlocked {
                statsRecorder.recordBlockedRequest()
            }
        }
        connection.lastActivity = Date()
        tcpConnections[key] = connection
    }

    private func writeTCP(
        packet: DNSPacket,
        sequence: UInt32,
        acknowledgment: UInt32,
        flags: UInt8
    ) {
        guard let response = DNSPacketWriter.tcpResponse(
            for: packet,
            sequenceNumber: sequence,
            acknowledgmentNumber: acknowledgment,
            flags: flags
        ) else { return }
        write(response, version: packet.version)
    }

    private func write(_ packet: Data, version: DNSIPVersion) {
        let addressFamily = version == .ipv4 ? AF_INET : AF_INET6
        packetFlow.writePackets([packet], withProtocols: [NSNumber(value: addressFamily)])
    }

    private static func udpResponsePayload(_ payload: Data) -> Data {
        guard payload.count > maximumUDPResponseBytes else { return payload }
        guard let message = DNSMessage(data: payload) else {
            let identifier = payload.count >= 2
                ? UInt16(payload[payload.startIndex]) << 8
                    | UInt16(payload[payload.index(payload.startIndex, offsetBy: 1)])
                : 0
            return DNSMessage.serverFailureResponse(id: identifier)
        }
        return message.truncatedResponse()
    }

    private func loadBlocklist(operation: String) {
        guard let group = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: BuildEnvironment.appGroupIdentifier
        ) else {
            blocklist = []
            PacketTunnelTelemetry.event(operation)
            return
        }

        let url = group.appendingPathComponent("Library/Application Support/Blocklists/blocklist.txt")
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            blocklist = []
            dnsService.update(blocklist: blocklist, filteringEnabled: false)
            PacketTunnelTelemetry.event(operation)
            return
        }

        blocklist = Set(text.split(whereSeparator: \.isNewline).compactMap {
            DNSDomainMatcher.normalize(String($0))
        })
        PacketTunnelTelemetry.event(operation)
    }

    private func refreshPolicy() {
        lastPolicyRefresh = Date()
        filteringEnabled = subscriptionAccess.hasAccess()
        dnsService.update(blocklist: blocklist, filteringEnabled: filteringEnabled)
    }

    private func refreshPolicyIfNeeded() {
        guard Date().timeIntervalSince(lastPolicyRefresh) >= 30 else { return }
        refreshPolicy()
    }

    private func removeTCPConnection(_ key: TCPConnectionKey) {
        guard let connection = tcpConnections.removeValue(forKey: key) else { return }
        for requestID in connection.pendingOrder {
            tcpTasks.removeValue(forKey: requestID)?.cancel()
        }
    }

    private func removeExpiredTCPConnections() {
        let cutoff = Date().addingTimeInterval(-120)
        let expired = tcpConnections.compactMap { key, connection in
            connection.lastActivity < cutoff ? key : nil
        }
        expired.forEach(removeTCPConnection)
    }
}

private enum TCPFlags {
    static let fin: UInt8 = 0x01
    static let rst: UInt8 = 0x04
    static let psh: UInt8 = 0x08
    static let ack: UInt8 = 0x10
    static let syn: UInt8 = 0x02
}

private struct TCPConnectionKey: Hashable {
    let version: DNSIPVersion
    let sourceAddress: Data
    let destinationAddress: Data
    let sourcePort: UInt16
    let destinationPort: UInt16

    init(packet: DNSPacket) {
        version = packet.version
        sourceAddress = packet.sourceAddress
        destinationAddress = packet.destinationAddress
        sourcePort = packet.sourcePort
        destinationPort = packet.destinationPort
    }
}

private struct TCPConnection {
    var template: DNSPacket
    var clientNextSequence: UInt32
    var serverNextSequence: UInt32
    var established: Bool
    var inputBuffer = Data()
    var pendingOrder: [UUID] = []
    var completed: [UUID: DNSResolutionResult] = [:]
    var lastActivity = Date()
}

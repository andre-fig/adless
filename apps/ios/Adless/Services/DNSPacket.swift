import Foundation

enum DNSIPVersion: Equatable {
    case ipv4
    case ipv6
}

enum DNSTransportProtocol: Equatable {
    case udp
    case tcp
}

struct DNSPacket {
    let version: DNSIPVersion
    let transport: DNSTransportProtocol
    let sourceAddress: Data
    let destinationAddress: Data
    let sourcePort: UInt16
    let destinationPort: UInt16
    let payload: Data
    let tcpSequenceNumber: UInt32?
    let tcpAcknowledgmentNumber: UInt32?
    let tcpFlags: UInt8
    let tcpWindow: UInt16

    init?(data: Data) {
        guard let first = data.first else { return nil }
        switch first >> 4 {
        case 4:
            self.init(ipv4: data)
        case 6:
            self.init(ipv6: data)
        default:
            return nil
        }
    }

    private init?(ipv4 data: Data) {
        guard data.count >= 20, data[0] & 0x0f >= 5 else { return nil }
        let headerLength = Int(data[0] & 0x0f) * 4
        guard data.count >= headerLength,
              let totalLength = data.uint16(at: 2),
              Int(totalLength) >= headerLength,
              Int(totalLength) <= data.count else { return nil }

        let fragment = data.uint16(at: 6) ?? 0
        // The packet flow does not reassemble IPv4 fragments. Reject both
        // non-zero offsets and a more-fragments flag to avoid parsing a
        // partial DNS transport header as a complete packet.
        guard fragment & 0x3fff == 0 else { return nil }
        guard let transport = Self.transport(for: data[9]) else { return nil }

        let source = data.subdata(in: 12..<16)
        let destination = data.subdata(in: 16..<20)
        let transportData = data.subdata(in: headerLength..<Int(totalLength))
        guard let fields = Self.transportFields(transportData, transport: transport) else { return nil }

        self.version = .ipv4
        self.transport = transport
        self.sourceAddress = source
        self.destinationAddress = destination
        self.sourcePort = fields.sourcePort
        self.destinationPort = fields.destinationPort
        self.payload = fields.payload
        self.tcpSequenceNumber = fields.sequenceNumber
        self.tcpAcknowledgmentNumber = fields.acknowledgmentNumber
        self.tcpFlags = fields.flags
        self.tcpWindow = fields.window
    }

    private init?(ipv6 data: Data) {
        guard data.count >= 40,
              let payloadLength = data.uint16(at: 4),
              40 + Int(payloadLength) <= data.count else { return nil }

        let source = data.subdata(in: 8..<24)
        let destination = data.subdata(in: 24..<40)
        var nextHeader = data[6]
        var transportOffset = 40
        let packetEnd = 40 + Int(payloadLength)

        // Skip standard IPv6 extension headers. Fragmented packets cannot be
        // reconstructed by a packet tunnel without a full reassembly cache,
        // so only the unfragmented first packet is accepted here.
        while nextHeader == 0 || nextHeader == 43 || nextHeader == 44 || nextHeader == 51 || nextHeader == 60 {
            guard transportOffset + 2 <= packetEnd else { return nil }
            if nextHeader == 44 {
                guard transportOffset + 8 <= packetEnd,
                      let fragment = data.uint16(at: transportOffset + 2),
                      fragment == 0 else { return nil }
                nextHeader = data[transportOffset]
                transportOffset += 8
                continue
            }

            let extensionLength: Int
            if nextHeader == 51 {
                extensionLength = (Int(data[transportOffset + 1]) + 2) * 4
            } else {
                extensionLength = (Int(data[transportOffset + 1]) + 1) * 8
            }
            guard extensionLength >= 8, transportOffset + extensionLength <= packetEnd else {
                return nil
            }
            nextHeader = data[transportOffset]
            transportOffset += extensionLength
        }

        guard let transport = Self.transport(for: nextHeader),
              let fields = Self.transportFields(
                  data.subdata(in: transportOffset..<packetEnd),
                  transport: transport
              ) else { return nil }

        self.version = .ipv6
        self.transport = transport
        self.sourceAddress = source
        self.destinationAddress = destination
        self.sourcePort = fields.sourcePort
        self.destinationPort = fields.destinationPort
        self.payload = fields.payload
        self.tcpSequenceNumber = fields.sequenceNumber
        self.tcpAcknowledgmentNumber = fields.acknowledgmentNumber
        self.tcpFlags = fields.flags
        self.tcpWindow = fields.window
    }

    private struct TransportFields {
        let sourcePort: UInt16
        let destinationPort: UInt16
        let payload: Data
        let sequenceNumber: UInt32?
        let acknowledgmentNumber: UInt32?
        let flags: UInt8
        let window: UInt16
    }

    private static func transport(for number: UInt8) -> DNSTransportProtocol? {
        switch number {
        case 17: return .udp
        case 6: return .tcp
        default: return nil
        }
    }

    private static func transportFields(_ data: Data, transport: DNSTransportProtocol) -> TransportFields? {
        guard data.count >= 8,
              let sourcePort = data.uint16(at: 0),
              let destinationPort = data.uint16(at: 2) else { return nil }

        switch transport {
        case .udp:
            guard let length = data.uint16(at: 4), Int(length) >= 8,
                  Int(length) <= data.count else { return nil }
            return TransportFields(
                sourcePort: sourcePort,
                destinationPort: destinationPort,
                payload: data.subdata(in: 8..<Int(length)),
                sequenceNumber: nil,
                acknowledgmentNumber: nil,
                flags: 0,
                window: 0
            )
        case .tcp:
            guard data.count >= 20,
                  let sequenceNumber = data.uint32(at: 4),
                  let acknowledgmentNumber = data.uint32(at: 8),
                  let window = data.uint16(at: 14) else { return nil }
            let headerLength = Int(data[12] >> 4) * 4
            guard headerLength >= 20, headerLength <= data.count else { return nil }
            return TransportFields(
                sourcePort: sourcePort,
                destinationPort: destinationPort,
                payload: data.subdata(in: headerLength..<data.count),
                sequenceNumber: sequenceNumber,
                acknowledgmentNumber: acknowledgmentNumber,
                flags: data[13],
                window: window
            )
        }
    }
}

enum DNSPacketWriter {
    static func udpResponse(for request: DNSPacket, payload: Data) -> Data? {
        guard request.transport == .udp, payload.count <= UInt16.max - 8 else { return nil }
        let udpLength = 8 + payload.count
        var transport = Data()
        transport.appendUInt16(request.destinationPort)
        transport.appendUInt16(request.sourcePort)
        transport.appendUInt16(UInt16(udpLength))
        transport.appendUInt16(0)
        transport.append(payload)

        let checksum = checksum(
            pseudoHeader(source: request.destinationAddress,
                         destination: request.sourceAddress,
                         protocolNumber: 17,
                         length: udpLength)
                + transport
        )
        transport.replaceUInt16(checksum == 0 ? 0xffff : checksum, at: 6)
        return ipPacket(
            version: request.version,
            source: request.destinationAddress,
            destination: request.sourceAddress,
            protocolNumber: 17,
            payload: transport
        )
    }

    static func tcpResponse(
        for request: DNSPacket,
        sequenceNumber: UInt32,
        acknowledgmentNumber: UInt32,
        flags: UInt8,
        payload: Data = Data()
    ) -> Data? {
        guard request.transport == .tcp,
              payload.count <= Int(UInt16.max) - 20 - 20 else { return nil }
        var transport = Data()
        transport.appendUInt16(request.destinationPort)
        transport.appendUInt16(request.sourcePort)
        transport.appendUInt32(sequenceNumber)
        transport.appendUInt32(acknowledgmentNumber)
        transport.append(UInt8(5 << 4))
        transport.append(flags)
        transport.appendUInt16(request.tcpWindow == 0 ? 65_535 : request.tcpWindow)
        transport.appendUInt16(0)
        transport.appendUInt16(0)
        transport.append(payload)

        let checksum = checksum(
            pseudoHeader(source: request.destinationAddress,
                         destination: request.sourceAddress,
                         protocolNumber: 6,
                         length: transport.count)
                + transport
        )
        transport.replaceUInt16(checksum == 0 ? 0xffff : checksum, at: 16)
        return ipPacket(
            version: request.version,
            source: request.destinationAddress,
            destination: request.sourceAddress,
            protocolNumber: 6,
            payload: transport
        )
    }

    private static func ipPacket(
        version: DNSIPVersion,
        source: Data,
        destination: Data,
        protocolNumber: UInt8,
        payload: Data
    ) -> Data? {
        switch version {
        case .ipv4:
            guard source.count == 4, destination.count == 4,
                  payload.count <= UInt16.max - 20 else { return nil }
            var packet = Data(repeating: 0, count: 20)
            packet[0] = 0x45
            packet.replaceUInt16(UInt16(20 + payload.count), at: 2)
            packet.replaceUInt16(0x4000, at: 6)
            packet[8] = 64
            packet[9] = protocolNumber
            packet.replaceBytes(source, at: 12)
            packet.replaceBytes(destination, at: 16)
            packet.replaceUInt16(checksum(packet), at: 10)
            packet.append(payload)
            return packet
        case .ipv6:
            guard source.count == 16, destination.count == 16,
                  payload.count <= UInt16.max else { return nil }
            var packet = Data(repeating: 0, count: 40)
            packet[0] = 0x60
            packet.replaceUInt16(UInt16(payload.count), at: 4)
            packet[6] = protocolNumber
            packet[7] = 64
            packet.replaceBytes(source, at: 8)
            packet.replaceBytes(destination, at: 24)
            packet.append(payload)
            return packet
        }
    }

    private static func pseudoHeader(source: Data, destination: Data, protocolNumber: UInt8, length: Int) -> Data {
        var header = Data()
        header.append(source)
        header.append(destination)
        if source.count == 4 {
            header.append(0)
            header.append(protocolNumber)
            header.appendUInt16(UInt16(length))
        } else {
            header.appendUInt32(UInt32(length))
            header.append(contentsOf: [0, 0, 0, protocolNumber])
        }
        return header
    }

    private static func checksum(_ data: Data) -> UInt16 {
        var sum: UInt32 = 0
        var index = 0
        while index + 1 < data.count {
            sum += UInt32(data[index]) << 8 | UInt32(data[index + 1])
            index += 2
        }
        if index < data.count { sum += UInt32(data[index]) << 8 }
        while sum >> 16 != 0 { sum = (sum & 0xffff) + (sum >> 16) }
        return ~UInt16(sum & 0xffff)
    }
}

private extension Data {
    func uint16(at offset: Int) -> UInt16? {
        guard offset >= 0, offset + 2 <= count else { return nil }
        return UInt16(self[offset]) << 8 | UInt16(self[offset + 1])
    }

    func uint32(at offset: Int) -> UInt32? {
        guard let high = uint16(at: offset), let low = uint16(at: offset + 2) else { return nil }
        return UInt32(high) << 16 | UInt32(low)
    }

    mutating func appendUInt16(_ value: UInt16) {
        append(UInt8(value >> 8))
        append(UInt8(value & 0xff))
    }

    mutating func appendUInt32(_ value: UInt32) {
        append(UInt8((value >> 24) & 0xff))
        append(UInt8((value >> 16) & 0xff))
        append(UInt8((value >> 8) & 0xff))
        append(UInt8(value & 0xff))
    }

    mutating func replaceUInt16(_ value: UInt16, at offset: Int) {
        self[offset] = UInt8(value >> 8)
        self[offset + 1] = UInt8(value & 0xff)
    }

    mutating func replaceBytes(_ bytes: Data, at offset: Int) {
        replaceSubrange(offset..<(offset + bytes.count), with: bytes)
    }
}

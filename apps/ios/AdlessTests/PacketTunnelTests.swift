import Foundation
import XCTest
@testable import Adless

@MainActor
final class PacketTunnelTests: XCTestCase {
    func testDNSMessagePreservesQuestionTypesAndBlocksAAndAAAALocally() throws {
        let aQuery = dnsQuery(name: "cdn.ads.example", type: 1)
        let aMessage = try XCTUnwrap(DNSMessage(data: aQuery))
        let aResponse = try XCTUnwrap(DNSMessage(data: aMessage.blockedResponse()))
        XCTAssertEqual(aResponse.answers.first?.rdata, Data([0, 0, 0, 0]))

        let aaaaQuery = dnsQuery(name: "cdn.ads.example", type: 28)
        let aaaaMessage = try XCTUnwrap(DNSMessage(data: aaaaQuery))
        let aaaaResponse = try XCTUnwrap(DNSMessage(data: aaaaMessage.blockedResponse()))
        XCTAssertEqual(aaaaResponse.answers.first?.rdata, Data(repeating: 0, count: 16))
    }

    func testBlockedResponseUsesNODATAForNonAddressTypes() throws {
        for type in [UInt16(5), 12, 15, 16, 33, 64, 65] {
            let message = try XCTUnwrap(DNSMessage(data: dnsQuery(name: "ads.example", type: type)))
            let response = try XCTUnwrap(DNSMessage(data: message.blockedResponse()))
            XCTAssertTrue(response.answers.isEmpty, "type \(type) should receive NODATA")
            XCTAssertTrue(response.isResponse)
        }
    }

    func testMalformedDNSAndFragmentedPacketsAreRejected() throws {
        XCTAssertNil(DNSMessage(data: Data([0, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 3, 97])))

        var fragmented = ipv4UDP(
            source: [192, 0, 2, 10],
            destination: [10, 255, 255, 2],
            sourcePort: 52_000,
            destinationPort: 53,
            payload: dnsQuery(name: "example.com", type: 1)
        )
        fragmented[6] = 0x20
        fragmented[7] = 0
        XCTAssertNil(DNSPacket(data: fragmented))
    }

    func testDNSMessageAcceptsCompressedNamesAndAdditionalRecords() throws {
        var data = dnsQuery(name: "example.com", type: 65)
        data[10] = 0
        data[11] = 1 // one OPT record
        data.append(contentsOf: [0, 41, 0, 0, 0, 0, 0, 0, 0, 0, 0])
        XCTAssertNotNil(DNSMessage(data: data))

        var compressed = Data([0x12, 0x34, 0x01, 0x00, 0, 2, 0, 0, 0, 0, 0, 0])
        compressed.append(contentsOf: [7])
        compressed.append(Data("example".utf8))
        compressed.append(contentsOf: [3])
        compressed.append(Data("com".utf8))
        compressed.append(contentsOf: [0, 0, 1, 0, 1])
        compressed.append(contentsOf: [0xc0, 0x0c, 0, 28, 0, 1])
        let compressedMessage = try XCTUnwrap(DNSMessage(data: compressed))
        XCTAssertEqual(compressedMessage.questions.count, 2)
        XCTAssertEqual(compressedMessage.firstQuestionName(), "example.com")
    }

    func testIPv4UDPParsingWritingAndEndpointSwap() throws {
        let query = dnsQuery(name: "example.com", type: 1)
        let packetData = ipv4UDP(
            source: [192, 0, 2, 10],
            destination: [10, 255, 255, 2],
            sourcePort: 52_000,
            destinationPort: 53,
            payload: query
        )
        let packet = try XCTUnwrap(DNSPacket(data: packetData))
        XCTAssertEqual(packet.version, .ipv4)
        XCTAssertEqual(packet.transport, .udp)
        XCTAssertEqual(packet.sourcePort, 52_000)
        XCTAssertEqual(packet.destinationPort, 53)
        XCTAssertEqual(packet.payload, query)

        let responseData = try XCTUnwrap(DNSPacketWriter.udpResponse(for: packet, payload: query))
        let response = try XCTUnwrap(DNSPacket(data: responseData))
        XCTAssertEqual(response.sourceAddress, packet.destinationAddress)
        XCTAssertEqual(response.destinationAddress, packet.sourceAddress)
        XCTAssertEqual(response.sourcePort, 53)
        XCTAssertEqual(response.destinationPort, 52_000)
        XCTAssertEqual(response.payload, query)
    }

    func testIPv6UDPParsingAndWriting() throws {
        let query = dnsQuery(name: "example.com", type: 28)
        let packetData = ipv6UDP(
            source: Array(repeating: UInt8(0), count: 15) + [1],
            destination: [0xfd, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x53],
            sourcePort: 54_321,
            destinationPort: 53,
            payload: query
        )
        let packet = try XCTUnwrap(DNSPacket(data: packetData))
        XCTAssertEqual(packet.version, .ipv6)
        XCTAssertEqual(packet.payload, query)
        XCTAssertNotNil(DNSPacketWriter.udpResponse(for: packet, payload: query))
    }

    func testTCPParsingWritingAndSequenceFields() throws {
        let query = Data([0, 3, 1, 2, 3])
        let packetData = ipv4TCP(
            source: [192, 0, 2, 10],
            destination: [10, 255, 255, 2],
            sourcePort: 52_001,
            destinationPort: 53,
            sequenceNumber: 100,
            acknowledgmentNumber: 0,
            flags: 0x02,
            payload: query
        )
        let packet = try XCTUnwrap(DNSPacket(data: packetData))
        XCTAssertEqual(packet.transport, .tcp)
        XCTAssertEqual(packet.tcpSequenceNumber, 100)
        XCTAssertEqual(packet.tcpAcknowledgmentNumber, 0)
        XCTAssertEqual(packet.tcpFlags, 0x02)
        XCTAssertEqual(packet.payload, query)

        let responseData = try XCTUnwrap(DNSPacketWriter.tcpResponse(
            for: packet,
            sequenceNumber: 200,
            acknowledgmentNumber: 105,
            flags: 0x12,
            payload: Data([9, 8])
        ))
        let response = try XCTUnwrap(DNSPacket(data: responseData))
        XCTAssertEqual(response.sourcePort, 53)
        XCTAssertEqual(response.destinationPort, 52_001)
        XCTAssertEqual(response.tcpSequenceNumber, 200)
        XCTAssertEqual(response.tcpAcknowledgmentNumber, 105)
        XCTAssertEqual(response.tcpFlags, 0x12)
        XCTAssertEqual(response.payload, Data([9, 8]))
    }

    func testDomainMatcherUsesSuffixBoundariesForAllDNSQueryTypes() {
        let entries: Set<String> = ["ads.example.com"]
        XCTAssertTrue(DNSDomainMatcher.matches(domain: "img.ads.example.com.", entries: entries))
        XCTAssertFalse(DNSDomainMatcher.matches(domain: "ads.example.com.evil", entries: entries))
    }

    private func dnsQuery(name: String, type: UInt16) -> Data {
        var data = Data([0x10, 0x20, 0x01, 0x00, 0, 1, 0, 0, 0, 0, 0, 0])
        for label in name.split(separator: ".") {
            data.append(UInt8(label.utf8.count))
            data.append(contentsOf: label.utf8)
        }
        data.append(contentsOf: [0, UInt8(type >> 8), UInt8(type & 0xff), 0, 1])
        return data
    }

    private func ipv4UDP(
        source: [UInt8], destination: [UInt8], sourcePort: UInt16,
        destinationPort: UInt16, payload: Data
    ) -> Data {
        var udp = Data()
        udp.append(contentsOf: [UInt8(sourcePort >> 8), UInt8(sourcePort & 0xff)])
        udp.append(contentsOf: [UInt8(destinationPort >> 8), UInt8(destinationPort & 0xff)])
        udp.append(contentsOf: [UInt8((payload.count + 8) >> 8), UInt8((payload.count + 8) & 0xff), 0, 0])
        udp.append(payload)

        var packet = Data(repeating: 0, count: 20)
        packet[0] = 0x45
        packet[2] = UInt8((packet.count + udp.count) >> 8)
        packet[3] = UInt8((packet.count + udp.count) & 0xff)
        packet[8] = 64
        packet[9] = 17
        packet.replaceSubrange(12..<16, with: source)
        packet.replaceSubrange(16..<20, with: destination)
        packet.append(udp)
        return packet
    }

    private func ipv6UDP(
        source: [UInt8], destination: [UInt8], sourcePort: UInt16,
        destinationPort: UInt16, payload: Data
    ) -> Data {
        var udp = Data()
        udp.append(contentsOf: [UInt8(sourcePort >> 8), UInt8(sourcePort & 0xff)])
        udp.append(contentsOf: [UInt8(destinationPort >> 8), UInt8(destinationPort & 0xff)])
        udp.append(contentsOf: [UInt8((payload.count + 8) >> 8), UInt8((payload.count + 8) & 0xff), 0, 0])
        udp.append(payload)

        var packet = Data(repeating: 0, count: 40)
        packet[0] = 0x60
        packet[4] = UInt8(udp.count >> 8)
        packet[5] = UInt8(udp.count & 0xff)
        packet[6] = 17
        packet[7] = 64
        packet.replaceSubrange(8..<24, with: source)
        packet.replaceSubrange(24..<40, with: destination)
        packet.append(udp)
        return packet
    }

    private func ipv4TCP(
        source: [UInt8], destination: [UInt8], sourcePort: UInt16,
        destinationPort: UInt16, sequenceNumber: UInt32,
        acknowledgmentNumber: UInt32, flags: UInt8, payload: Data
    ) -> Data {
        var tcp = Data()
        tcp.append(contentsOf: [UInt8(sourcePort >> 8), UInt8(sourcePort & 0xff)])
        tcp.append(contentsOf: [UInt8(destinationPort >> 8), UInt8(destinationPort & 0xff)])
        tcp.append(contentsOf: [
            UInt8(sequenceNumber >> 24), UInt8(sequenceNumber >> 16),
            UInt8(sequenceNumber >> 8), UInt8(sequenceNumber & 0xff),
            UInt8(acknowledgmentNumber >> 24), UInt8(acknowledgmentNumber >> 16),
            UInt8(acknowledgmentNumber >> 8), UInt8(acknowledgmentNumber & 0xff)
        ])
        tcp.append(contentsOf: [0x50, flags, 0xff, 0xff, 0, 0, 0, 0])
        tcp.append(payload)

        var packet = Data(repeating: 0, count: 20)
        packet[0] = 0x45
        packet[2] = UInt8((packet.count + tcp.count) >> 8)
        packet[3] = UInt8((packet.count + tcp.count) & 0xff)
        packet[8] = 64
        packet[9] = 6
        packet.replaceSubrange(12..<16, with: source)
        packet.replaceSubrange(16..<20, with: destination)
        packet.append(tcp)
        return packet
    }
}

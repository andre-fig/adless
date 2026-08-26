import Foundation

struct DNSHeader {
    var id: UInt16
    var flags: UInt16
    var qdCount: UInt16
    var anCount: UInt16
    var nsCount: UInt16
    var arCount: UInt16
}

struct DNSQuestion {
    let name: String
    let type: UInt16
    let cls: UInt16
}

struct DNSResourceRecord {
    let name: String
    let type: UInt16
    let cls: UInt16
    let ttl: UInt32
    let rdata: Data
}

/// A bounded DNS wire parser used by both the application tests and the
/// Packet Tunnel. It accepts all record types and never exposes packet bytes
/// to diagnostics.
struct DNSMessage {
    var header: DNSHeader
    var questions: [DNSQuestion]
    var answers: [DNSResourceRecord]

    init?(data: Data) {
        var reader = DNSWireReader(data: data)
        guard let header = reader.readHeader(), header.qdCount > 0,
              header.qdCount <= 16 else { return nil }

        var questions: [DNSQuestion] = []
        questions.reserveCapacity(Int(header.qdCount))
        for _ in 0..<header.qdCount {
            guard let question = reader.readQuestion() else { return nil }
            questions.append(question)
        }

        // Validate the rest of the message, including EDNS and compressed
        // names. Keep answer records so local responses can be bounded or
        // inspected by tests without reparsing raw wire bytes.
        var answers: [DNSResourceRecord] = []
        answers.reserveCapacity(Int(header.anCount))
        for _ in 0..<header.anCount {
            guard let answer = reader.readResourceRecord() else { return nil }
            answers.append(answer)
        }
        for _ in 0..<header.nsCount {
            guard reader.skipResourceRecord() else { return nil }
        }
        for _ in 0..<header.arCount {
            guard reader.skipResourceRecord() else { return nil }
        }
        guard reader.isAtEnd else { return nil }

        self.header = header
        self.questions = questions
        self.answers = answers
    }

    var isResponse: Bool {
        header.flags & 0x8000 != 0
    }

    func encode() -> Data {
        var data = Data()
        data.appendUInt16(header.id)
        data.appendUInt16(header.flags)
        data.appendUInt16(UInt16(questions.count))
        data.appendUInt16(UInt16(answers.count))
        data.appendUInt16(0)
        data.appendUInt16(0)

        for question in questions {
            data.appendDNSName(question.name)
            data.appendUInt16(question.type)
            data.appendUInt16(question.cls)
        }

        for answer in answers {
            data.appendDNSName(answer.name)
            data.appendUInt16(answer.type)
            data.appendUInt16(answer.cls)
            data.appendUInt32(answer.ttl)
            data.appendUInt16(UInt16(answer.rdata.count))
            data.append(answer.rdata)
        }
        return data
    }

    func serverFailureResponse() -> Data {
        var response = self
        response.header.flags = (header.flags & 0x0100) | 0x8082
        response.header.nsCount = 0
        response.header.arCount = 0
        response.answers = []
        return response.encode()
    }

    /// Produces a small response with the truncation bit set so a DNS client
    /// can retry the same question over TCP instead of receiving an
    /// oversized IP packet from the packet flow.
    func truncatedResponse() -> Data {
        var response = self
        response.header.flags = (header.flags & 0x0100) | 0x8200
        response.header.nsCount = 0
        response.header.arCount = 0
        response.answers = []
        return response.encode()
    }

    static func serverFailureResponse(id: UInt16) -> Data {
        var data = Data()
        data.appendUInt16(id)
        data.appendUInt16(0x8082)
        data.appendUInt16(0)
        data.appendUInt16(0)
        data.appendUInt16(0)
        data.appendUInt16(0)
        return data
    }

    func blockedResponse() -> Data {
        var response = self
        response.header.flags = (header.flags & 0x0100) | 0x8180
        response.header.nsCount = 0
        response.header.arCount = 0
        response.answers = []

        guard let question = questions.first else { return response.encode() }
        switch question.type {
        case 1: // A
            response.answers = [DNSResourceRecord(
                name: question.name,
                type: 1,
                cls: question.cls,
                ttl: 0,
                rdata: Data([0, 0, 0, 0])
            )]
        case 28: // AAAA
            response.answers = [DNSResourceRecord(
                name: question.name,
                type: 28,
                cls: question.cls,
                ttl: 0,
                rdata: Data(repeating: 0, count: 16)
            )]
        default:
            // NODATA is valid for MX, TXT, SRV, HTTPS, SVCB, PTR and every
            // other type. The query is still answered locally and never sent
            // upstream.
            break
        }
        return response.encode()
    }

    func firstQuestionName() -> String? {
        questions.first?.name
    }
}

enum DNSDomainMatcher {
    private static let reservedNames: Set<String> = [
        "localhost",
        "localhost.localdomain",
        "broadcasthost",
        "ip6-allnodes",
        "ip6-allrouters",
        "ip6-localhost"
    ]

    static func normalize(_ value: String) -> String? {
        let candidate = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()

        guard !candidate.isEmpty,
              candidate.count <= 253,
              candidate.contains("."),
              !candidate.contains("*"),
              !candidate.contains("/"),
              !candidate.contains("|"),
              !candidate.contains("^"),
              !candidate.contains(":"),
              !reservedNames.contains(candidate),
              !isIPv4Address(candidate),
              candidate.unicodeScalars.allSatisfy({ $0.value < 128 }) else {
            return nil
        }

        let labels = candidate.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.allSatisfy({ label in
            guard !label.isEmpty, label.count <= 63,
                  let first = label.first, let last = label.last,
                  isASCIIAlphaNumeric(first), isASCIIAlphaNumeric(last) else {
                return false
            }
            return label.allSatisfy { isASCIIAlphaNumeric($0) || $0 == "-" }
        }) else {
            return nil
        }
        return candidate
    }

    static func matches(domain: String, entries: Set<String>) -> Bool {
        guard let normalized = normalize(domain) else { return false }
        let labels = normalized.split(separator: ".")
        for index in labels.indices {
            if entries.contains(labels[index...].joined(separator: ".")) {
                return true
            }
        }
        return false
    }

    private static func isASCIIAlphaNumeric(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first,
              character.unicodeScalars.count == 1 else { return false }
        return (48...57).contains(scalar.value)
            || (65...90).contains(scalar.value)
            || (97...122).contains(scalar.value)
    }

    private static func isIPv4Address(_ value: String) -> Bool {
        let parts = value.split(separator: ".")
        return parts.count == 4 && parts.allSatisfy { part in
            guard let number = Int(part) else { return false }
            return (0...255).contains(number)
        }
    }
}

private struct DNSWireReader {
    private let data: Data
    private var offset = 0

    init(data: Data) {
        self.data = data
    }

    var isAtEnd: Bool { offset == data.count }

    mutating func readHeader() -> DNSHeader? {
        guard let id = readUInt16(), let flags = readUInt16(),
              let qdCount = readUInt16(), let anCount = readUInt16(),
              let nsCount = readUInt16(), let arCount = readUInt16() else {
            return nil
        }
        return DNSHeader(id: id, flags: flags, qdCount: qdCount,
                         anCount: anCount, nsCount: nsCount, arCount: arCount)
    }

    mutating func readQuestion() -> DNSQuestion? {
        guard let name = readName(), let type = readUInt16(),
              let cls = readUInt16() else { return nil }
        return DNSQuestion(name: name, type: type, cls: cls)
    }

    mutating func skipResourceRecord() -> Bool {
        guard readName() != nil, readUInt16() != nil, readUInt16() != nil,
              readUInt32() != nil, let length = readUInt16(),
              readBytes(count: Int(length)) != nil else { return false }
        return true
    }

    mutating func readResourceRecord() -> DNSResourceRecord? {
        guard let name = readName(), let type = readUInt16(),
              let cls = readUInt16(), let ttl = readUInt32(),
              let length = readUInt16(), let rdata = readBytes(count: Int(length)) else {
            return nil
        }
        return DNSResourceRecord(name: name, type: type, cls: cls, ttl: ttl, rdata: rdata)
    }

    private mutating func readName() -> String? {
        var labels: [String] = []
        var cursor = offset
        var jumped = false
        var visitedPointers = Set<Int>()

        while true {
            guard let length = byte(at: cursor) else { return nil }
            if length == 0 {
                if !jumped { offset = cursor + 1 }
                return labels.joined(separator: ".")
            }
            if length & 0xc0 == 0xc0 {
                guard let next = byte(at: cursor + 1) else { return nil }
                let pointer = (Int(length & 0x3f) << 8) | Int(next)
                guard pointer < data.count, visitedPointers.insert(pointer).inserted else {
                    return nil
                }
                if !jumped {
                    offset = cursor + 2
                    jumped = true
                }
                cursor = pointer
                continue
            }
            guard length < 0x40,
                  let labelData = readBytes(at: cursor + 1, count: Int(length)),
                  let label = String(data: labelData, encoding: .utf8) else {
                return nil
            }
            labels.append(label)
            cursor += 1 + Int(length)
        }
    }

    private mutating func readUInt16() -> UInt16? {
        guard let high = byte(at: offset), let low = byte(at: offset + 1) else {
            return nil
        }
        offset += 2
        return UInt16(high) << 8 | UInt16(low)
    }

    private mutating func readUInt32() -> UInt32? {
        guard let first = readUInt16(), let second = readUInt16() else { return nil }
        return UInt32(first) << 16 | UInt32(second)
    }

    private mutating func readBytes(count: Int) -> Data? {
        guard let value = readBytes(at: offset, count: count) else { return nil }
        offset += count
        return value
    }

    private func readBytes(at position: Int, count: Int) -> Data? {
        guard position >= 0, count >= 0,
              position <= data.count, count <= data.count - position else { return nil }
        return data.subdata(in: position..<(position + count))
    }

    private func byte(at position: Int) -> UInt8? {
        guard position >= 0, position < data.count else { return nil }
        return data[position]
    }
}

private extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        var bigEndian = value.bigEndian
        Swift.withUnsafeBytes(of: &bigEndian) { append(contentsOf: $0) }
    }

    mutating func appendUInt32(_ value: UInt32) {
        var bigEndian = value.bigEndian
        Swift.withUnsafeBytes(of: &bigEndian) { append(contentsOf: $0) }
    }

    mutating func appendDNSName(_ name: String) {
        for label in name.split(separator: ".") {
            let bytes = Data(label.utf8)
            guard bytes.count <= 63 else { return }
            append(UInt8(bytes.count))
            append(bytes)
        }
        append(0)
    }
}

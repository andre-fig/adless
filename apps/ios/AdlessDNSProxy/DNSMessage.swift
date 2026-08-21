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

struct DNSMessage {
    var header: DNSHeader
    var questions: [DNSQuestion]
    var answers: [DNSResourceRecord]

    init?(data: Data) {
        var reader = DataReader(data)
        guard let header = reader.readHeader() else { return nil }
        self.header = header
        var qs: [DNSQuestion] = []
        for _ in 0..<header.qdCount {
            guard let q = reader.readQuestion() else { return nil }
            qs.append(q)
        }
        self.questions = qs
        self.answers = []
    }

    func encode() -> Data {
        var data = Data()
        data.appendUInt16(header.id)
        data.appendUInt16(header.flags)
        data.appendUInt16(header.qdCount)
        data.appendUInt16(UInt16(answers.count))
        data.appendUInt16(0)
        data.appendUInt16(0)

        for q in questions {
            data.appendName(q.name)
            data.appendUInt16(q.type)
            data.appendUInt16(q.cls)
        }

        for ans in answers {
            data.appendName(ans.name)
            data.appendUInt16(ans.type)
            data.appendUInt16(ans.cls)
            data.appendUInt32(ans.ttl)
            data.appendUInt16(UInt16(ans.rdata.count))
            data.append(ans.rdata)
        }

        return data
    }

    func serverFailureResponse() -> Data {
        var response = self
        response.header.flags = (header.flags & 0x0100) | 0x8082
        response.header.anCount = 0
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
}

private struct DataReader {
    private let data: Data
    private var offset: Int = 0

    init(_ data: Data) {
        self.data = data
    }

    mutating func readHeader() -> DNSHeader? {
        guard let id = readUInt16(), let flags = readUInt16(), let qd = readUInt16(), let an = readUInt16(), let ns = readUInt16(), let ar = readUInt16() else {
            return nil
        }
        return DNSHeader(id: id, flags: flags, qdCount: qd, anCount: an, nsCount: ns, arCount: ar)
    }

    mutating func readQuestion() -> DNSQuestion? {
        guard let name = readName(), let type = readUInt16(), let cls = readUInt16() else { return nil }
        return DNSQuestion(name: name, type: type, cls: cls)
    }

    private mutating func readUInt8() -> UInt8? {
        guard offset + 1 <= data.count else { return nil }
        let value = data[offset]
        offset += 1
        return value
    }

    private mutating func readUInt16() -> UInt16? {
        guard offset + 2 <= data.count else { return nil }
        let high = UInt16(data[offset])
        let low = UInt16(data[offset + 1])
        offset += 2
        return (high << 8) | low
    }

    private mutating func readName() -> String? {
        var labels: [String] = []
        while true {
            guard let length = readUInt8() else { return nil }
            if length == 0 { break }
            guard offset + Int(length) <= data.count else { return nil }
            let labelData = data[offset..<offset+Int(length)]
            offset += Int(length)
            if let label = String(data: labelData, encoding: .utf8) {
                labels.append(label)
            }
        }
        return labels.joined(separator: ".")
    }
}

private extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        var be = value.bigEndian
        Swift.withUnsafeBytes(of: &be) { append(contentsOf: $0) }
    }

    mutating func appendUInt32(_ value: UInt32) {
        var be = value.bigEndian
        Swift.withUnsafeBytes(of: &be) { append(contentsOf: $0) }
    }

    mutating func appendName(_ name: String) {
        let labels = name.split(separator: ".")
        for label in labels {
            let bytes = Data(label.utf8)
            append(UInt8(bytes.count))
            append(bytes)
        }
        append(UInt8(0))
    }
}

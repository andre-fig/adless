import Foundation
import Network

/// The transport used by the DNS proxy for permitted DNS queries.
///
/// The production client uses an ephemeral URLSession. The flow handlers
/// answer the two provider hostname bootstrap queries locally if the provider
/// process's own URLSession resolution is observed by the DNS proxy. This
/// prevents a recursive DoH lookup while retaining normal system TLS
/// certificate and hostname validation.
protocol DNSUpstreamTransport: Sendable {
    func resolve(_ query: Data) async throws -> Data
}

protocol DNSDoHHTTPClient: Sendable {
    func send(_ request: DNSDoHRequest) async throws -> DNSDoHHTTPResponse
}

struct DNSResolutionDiagnosticsSnapshot: Sendable, Equatable {
    let sampleCount: Int
    let successfulCount: Int
    let failedCount: Int
    let averageMilliseconds: Double
    let lastMilliseconds: Double?
    let lastProvider: String?
}

/// In-memory aggregate timing only. It deliberately does not retain a DNS
/// query, domain, transaction ID, URL, or response payload.
final class DNSResolutionDiagnostics: @unchecked Sendable {
    private let lock = NSLock()
    private var sampleCount = 0
    private var successfulCount = 0
    private var totalMilliseconds = 0.0
    private var lastMilliseconds: Double?
    private var lastProvider: String?

    func record(provider: DNSDoHEndpoint, duration: TimeInterval, succeeded: Bool) {
        lock.lock()
        defer { lock.unlock() }
        sampleCount += 1
        if succeeded {
            successfulCount += 1
        }
        let milliseconds = max(0, duration * 1_000)
        totalMilliseconds += milliseconds
        lastMilliseconds = milliseconds
        lastProvider = provider.hostname
    }

    func snapshot() -> DNSResolutionDiagnosticsSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return DNSResolutionDiagnosticsSnapshot(
            sampleCount: sampleCount,
            successfulCount: successfulCount,
            failedCount: sampleCount - successfulCount,
            averageMilliseconds: sampleCount == 0 ? 0 : totalMilliseconds / Double(sampleCount),
            lastMilliseconds: lastMilliseconds,
            lastProvider: lastProvider
        )
    }
}

actor DNSCircuitBreaker {
    static let failureThreshold = 3
    static let openDuration: TimeInterval = 15

    private let now: @Sendable () -> Date
    private var consecutiveFailures = 0
    private var openedUntil: Date?

    init(now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
    }

    func shouldBypassPrimary() -> Bool {
        guard let openedUntil else { return false }
        if now() < openedUntil {
            return true
        }
        self.openedUntil = nil
        consecutiveFailures = 0
        return false
    }

    func recordSuccess() {
        consecutiveFailures = 0
        openedUntil = nil
    }

    func recordFailure() {
        consecutiveFailures += 1
        if consecutiveFailures >= Self.failureThreshold {
            openedUntil = now().addingTimeInterval(Self.openDuration)
        }
    }

    func reset() {
        consecutiveFailures = 0
        openedUntil = nil
    }
}

/// Resets the primary circuit when the device changes network path.
final class DNSNetworkPathMonitor: @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.orbeworks.adless.dns-path")
    private let onChange: @Sendable () -> Void
    private var lastSignature: String?

    init(onChange: @escaping @Sendable () -> Void) {
        self.onChange = onChange
        monitor.pathUpdateHandler = { [weak self] path in
            self?.handle(path: path)
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }

    private func handle(path: NWPath) {
        let interfaces = path.availableInterfaces
            .map { String(describing: $0.type) }
            .sorted()
            .joined(separator: ",")
        let signature = "\(String(describing: path.status))|\(path.isExpensive)|\(path.isConstrained)|\(interfaces)"
        guard let previous = lastSignature else {
            lastSignature = signature
            return
        }
        lastSignature = signature
        if previous != signature {
            onChange()
        }
    }
}

struct DNSDoHEndpoint: Equatable, Sendable {
    let hostname: String
    let path: String
    let addresses: [String]

    static let cloudflare = DNSDoHEndpoint(
        hostname: "cloudflare-dns.com",
        path: "/dns-query",
        addresses: ["1.1.1.1", "1.0.0.1"]
    )

    static let quad9 = DNSDoHEndpoint(
        hostname: "dns.quad9.net",
        path: "/dns-query",
        addresses: ["9.9.9.9", "149.112.112.112"]
    )

    /// Answers bootstrap A/AAAA lookups for the DoH hostnames locally.
    ///
    /// This is a recursion guard for configurations where the DNS proxy also
    /// observes DNS resolution performed by its own URLSession. It does not
    /// affect user queries for other names and does not create a plaintext
    /// upstream path.
    static func bootstrapResponse(for query: Data) -> Data? {
        guard let header = DNSDoHWireMessage.header(from: query),
              header.questionCount == 1,
              DNSDoHWireMessage.isValid(query),
              let question = DNSDoHWireMessage.question(from: query),
              question.cls == 1 else {
            return nil
        }

        let normalized = question.name
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
        let endpoint = [cloudflare, quad9].first { $0.hostname == normalized }
        guard let endpoint else { return nil }

        let addresses: [Data]
        if question.type == 1 {
            addresses = endpoint.addresses.compactMap { address in
                let octets = address.split(separator: ".").compactMap { UInt8($0) }
                return octets.count == 4 ? Data(octets) : nil
            }
        } else if question.type != 28 {
            return nil
        } else {
            addresses = []
        }

        var response = Data()
        response.appendUInt16(header.id)
        response.appendUInt16((header.flags & 0x0100) | 0x8180)
        response.appendUInt16(1)
        response.appendUInt16(UInt16(addresses.count))
        response.appendUInt16(0)
        response.appendUInt16(0)
        response.append(query.subdata(in: 12..<question.endOffset))

        for address in addresses {
            response.append(contentsOf: [0xc0, 0x0c])
            response.appendUInt16(1)
            response.appendUInt16(1)
            response.appendUInt32(60)
            response.appendUInt16(UInt16(address.count))
            response.append(address)
        }

        return response
    }
}

struct DNSDoHRequest: Sendable {
    let endpoint: DNSDoHEndpoint
    let body: Data

    var headers: [String: String] {
        [
            "Host": endpoint.hostname,
            "Content-Type": "application/dns-message",
            "Accept": "application/dns-message",
            "Content-Length": String(body.count)
        ]
    }

    func encodedHTTPMessage() -> Data {
        var message = Data()
        message.append(Data("POST \(endpoint.path) HTTP/1.1\r\n".utf8))
        for (name, value) in headers {
            message.append(Data("\(name): \(value)\r\n".utf8))
        }
        message.append(Data("\r\n".utf8))
        message.append(body)
        return message
    }
}

struct DNSDoHHTTPResponse: Sendable {
    let statusCode: Int
    let headers: [String: String]
    let body: Data

    init(statusCode: Int, headers: [String: String], body: Data) {
        self.statusCode = statusCode
        var normalizedHeaders: [String: String] = [:]
        for (name, value) in headers {
            normalizedHeaders[name.lowercased()] = value
        }
        self.headers = normalizedHeaders
        self.body = body
    }

    var contentType: String? {
        headers["content-type"]?.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: true)
            .first
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    }
}

enum DNSDoHError: Error, Equatable {
    case invalidQuery
    case invalidHTTPStatus(Int)
    case invalidContentType
    case emptyResponse
    case invalidDNSResponse
    case responseTooLarge
    case timeout
    case transport
}

struct DNSDoHTransport: DNSUpstreamTransport, @unchecked Sendable {
    let endpoint: DNSDoHEndpoint
    private let client: any DNSDoHHTTPClient
    private let diagnostics: DNSResolutionDiagnostics?

    init(
        endpoint: DNSDoHEndpoint,
        client: (any DNSDoHHTTPClient)? = nil,
        diagnostics: DNSResolutionDiagnostics? = nil
    ) {
        self.endpoint = endpoint
        self.client = client ?? URLSessionDNSDoHHTTPClient()
        self.diagnostics = diagnostics
    }

    func resolve(_ query: Data) async throws -> Data {
        guard DNSDoHWireMessage.isValid(query),
              let queryHeader = DNSDoHWireMessage.header(from: query),
              queryHeader.questionCount > 0 else {
            throw DNSDoHError.invalidQuery
        }

        let startedAt = DispatchTime.now().uptimeNanoseconds
        var succeeded = false
        defer {
            let elapsed = DispatchTime.now().uptimeNanoseconds - startedAt
            diagnostics?.record(
                provider: endpoint,
                duration: TimeInterval(elapsed) / 1_000_000_000,
                succeeded: succeeded
            )
        }

        do {
            let response = try await client.send(DNSDoHRequest(endpoint: endpoint, body: query))
            guard (200..<300).contains(response.statusCode) else {
                throw DNSDoHError.invalidHTTPStatus(response.statusCode)
            }
            guard response.contentType == "application/dns-message" else {
                throw DNSDoHError.invalidContentType
            }
            guard !response.body.isEmpty else {
                throw DNSDoHError.emptyResponse
            }
            guard DNSDoHResponseValidator.validate(
                query: query,
                response: response.body,
                queryHeader: queryHeader
            ) else {
                throw DNSDoHError.invalidDNSResponse
            }
            succeeded = true
            return response.body
        } catch {
            throw error
        }
    }
}

struct DNSUpstreamResolver: DNSUpstreamTransport, @unchecked Sendable {
    let primary: any DNSUpstreamTransport
    let fallback: any DNSUpstreamTransport
    private let circuitBreaker: DNSCircuitBreaker
    private let networkPathMonitor: DNSNetworkPathMonitor?

    init(
        primary: any DNSUpstreamTransport,
        fallback: any DNSUpstreamTransport,
        circuitBreaker: DNSCircuitBreaker = DNSCircuitBreaker(),
        observesNetworkChanges: Bool = false
    ) {
        self.primary = primary
        self.fallback = fallback
        self.circuitBreaker = circuitBreaker
        if observesNetworkChanges {
            self.networkPathMonitor = DNSNetworkPathMonitor {
                Task { await circuitBreaker.reset() }
            }
        } else {
            self.networkPathMonitor = nil
        }
    }

    /// Creates one resolver, one ephemeral URLSession shared by both providers,
    /// and one circuit breaker for a single DNS proxy provider instance.
    static func production() -> DNSUpstreamResolver {
        let diagnostics = DNSResolutionDiagnostics()
        let httpClient = URLSessionDNSDoHHTTPClient()
        return DNSUpstreamResolver(
            primary: DNSDoHTransport(
                endpoint: .cloudflare,
                client: httpClient,
                diagnostics: diagnostics
            ),
            fallback: DNSDoHTransport(
                endpoint: .quad9,
                client: httpClient,
                diagnostics: diagnostics
            ),
            observesNetworkChanges: true
        )
    }

    func resolve(_ query: Data) async throws -> Data {
        if await circuitBreaker.shouldBypassPrimary() {
            return try await fallback.resolve(query)
        }

        do {
            // A valid NXDOMAIN response is returned normally and therefore
            // never reaches the fallback path.
            let response = try await primary.resolve(query)
            await circuitBreaker.recordSuccess()
            return response
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as DNSDoHError where error == .invalidQuery {
            throw error
        } catch {
            await circuitBreaker.recordFailure()
            return try await fallback.resolve(query)
        }
    }

    func resetCircuitBreaker() async {
        await circuitBreaker.reset()
    }
}

private struct DNSDoHWireHeader {
    let id: UInt16
    let flags: UInt16
    let questionCount: UInt16
    let answerCount: UInt16
    let authorityCount: UInt16
    let additionalCount: UInt16
}

private struct DNSDoHWireQuestion {
    let name: String
    let type: UInt16
    let cls: UInt16
    let endOffset: Int
}

private enum DNSDoHResponseValidator {
    static func validate(
        query: Data,
        response: Data,
        queryHeader: DNSDoHWireHeader? = nil
    ) -> Bool {
        guard let queryHeader = queryHeader ?? DNSDoHWireMessage.header(from: query),
              let responseHeader = DNSDoHWireMessage.header(from: response),
              let queryQuestion = DNSDoHWireMessage.question(from: query),
              let responseQuestion = DNSDoHWireMessage.question(from: response),
              DNSDoHWireMessage.isValid(response),
              responseHeader.id == queryHeader.id,
              responseHeader.flags & 0x8000 != 0,
              responseHeader.questionCount == queryHeader.questionCount,
              queryQuestion.type == responseQuestion.type,
              queryQuestion.cls == responseQuestion.cls,
              queryQuestion.name.caseInsensitiveCompare(responseQuestion.name) == .orderedSame else {
            return false
        }
        return true
    }
}

private enum DNSDoHWireMessage {
    static func header(from data: Data) -> DNSDoHWireHeader? {
        guard data.count >= 12,
              let id = data.uint16(at: 0),
              let flags = data.uint16(at: 2),
              let questionCount = data.uint16(at: 4),
              let answerCount = data.uint16(at: 6),
              let authorityCount = data.uint16(at: 8),
              let additionalCount = data.uint16(at: 10) else {
            return nil
        }
        return DNSDoHWireHeader(
            id: id,
            flags: flags,
            questionCount: questionCount,
            answerCount: answerCount,
            authorityCount: authorityCount,
            additionalCount: additionalCount
        )
    }

    static func isValid(_ data: Data) -> Bool {
        guard let header = header(from: data) else { return false }
        var offset = 12

        for _ in 0..<header.questionCount {
            guard skipName(in: data, offset: &offset), data.hasBytes(offset, count: 4) else {
                return false
            }
            offset += 4
        }

        for count in [header.answerCount, header.authorityCount, header.additionalCount] {
            for _ in 0..<count {
                guard skipName(in: data, offset: &offset), data.hasBytes(offset, count: 10),
                      let length = data.uint16(at: offset + 8) else {
                    return false
                }
                offset += 10
                guard data.hasBytes(offset, count: Int(length)) else { return false }
                offset += Int(length)
            }
        }

        return offset == data.count
    }

    static func question(from data: Data) -> DNSDoHWireQuestion? {
        var offset = 12
        guard let name = readName(in: data, offset: &offset),
              let type = data.uint16(at: offset),
              let cls = data.uint16(at: offset + 2) else {
            return nil
        }
        return DNSDoHWireQuestion(name: name, type: type, cls: cls, endOffset: offset + 4)
    }

    private static func readName(in data: Data, offset: inout Int) -> String? {
        var labels: [String] = []
        var cursor = offset
        var jumped = false
        var visitedPointers = Set<Int>()

        while true {
            guard data.hasBytes(cursor, count: 1) else { return nil }
            let length = data[cursor]
            if length == 0 {
                if !jumped { offset = cursor + 1 }
                return labels.joined(separator: ".")
            }
            if length & 0xc0 == 0xc0 {
                guard data.hasBytes(cursor, count: 2),
                      let pointer = data.uint16(at: cursor),
                      visitedPointers.insert(Int(pointer & 0x3fff)).inserted,
                      Int(pointer & 0x3fff) < data.count else {
                    return nil
                }
                if !jumped {
                    offset = cursor + 2
                    jumped = true
                }
                cursor = Int(pointer & 0x3fff)
                continue
            }
            guard length < 0x40, data.hasBytes(cursor + 1, count: Int(length)) else {
                return nil
            }
            let label = data.subdata(in: (cursor + 1)..<(cursor + 1 + Int(length)))
            guard let string = String(data: label, encoding: .utf8) else { return nil }
            labels.append(string)
            cursor += 1 + Int(length)
        }
    }

    private static func skipName(in data: Data, offset: inout Int) -> Bool {
        while true {
            guard data.hasBytes(offset, count: 1) else { return false }
            let length = data[offset]
            if length == 0 {
                offset += 1
                return true
            }
            if length & 0xc0 == 0xc0 {
                guard data.hasBytes(offset, count: 2) else { return false }
                offset += 2
                return true
            }
            guard length < 0x40, data.hasBytes(offset + 1, count: Int(length)) else {
                return false
            }
            offset += 1 + Int(length)
        }
    }
}

private final class URLSessionDNSDoHHTTPClient: DNSDoHHTTPClient, @unchecked Sendable {
    private let timeout: TimeInterval = 1.5
    private let maximumResponseSize = 64 * 1024
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        session = URLSession(configuration: configuration)
    }

    deinit {
        session.invalidateAndCancel()
    }

    func send(_ request: DNSDoHRequest) async throws -> DNSDoHHTTPResponse {
        guard let url = URL(string: "https://\(request.endpoint.hostname)\(request.endpoint.path)") else {
            throw DNSDoHError.transport
        }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.httpBody = request.body
        urlRequest.cachePolicy = .reloadIgnoringLocalCacheData
        urlRequest.timeoutInterval = timeout
        for (name, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }

        do {
            let (bytes, response) = try await session.bytes(for: urlRequest)
            guard let response = response as? HTTPURLResponse else {
                throw DNSDoHError.transport
            }
            var body = Data()
            for try await byte in bytes {
                guard body.count < maximumResponseSize else {
                    throw DNSDoHError.responseTooLarge
                }
                body.append(byte)
            }
            return DNSDoHHTTPResponse(
                statusCode: response.statusCode,
                headers: response.allHeaderFields.reduce(into: [String: String]()) { result, item in
                    guard let name = item.key as? String,
                          let value = item.value as? String else { return }
                    result[name] = value
                },
                body: body
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as URLError where error.code == .timedOut {
            throw DNSDoHError.timeout
        } catch let error as DNSDoHError {
            throw error
        } catch {
            throw DNSDoHError.transport
        }
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

    func uint16(at offset: Int) -> UInt16? {
        guard hasBytes(offset, count: 2) else { return nil }
        return UInt16(self[offset]) << 8 | UInt16(self[offset + 1])
    }

    func hasBytes(_ offset: Int, count: Int) -> Bool {
        offset >= 0 && count >= 0 && offset <= self.count && count <= self.count - offset
    }
}

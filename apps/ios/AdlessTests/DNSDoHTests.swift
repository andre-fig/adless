import Foundation
import XCTest
@testable import Adless

private actor RecordingDoHClient: DNSDoHHTTPClient {
    enum Outcome: Sendable {
        case response(DNSDoHHTTPResponse)
        case error(DNSDoHError)
    }

    private var outcomes: [Outcome]
    private let delayNanoseconds: UInt64
    private var requests: [DNSDoHRequest] = []

    init(outcomes: [Outcome], delayNanoseconds: UInt64 = 0) {
        self.outcomes = outcomes
        self.delayNanoseconds = delayNanoseconds
    }

    func send(_ request: DNSDoHRequest) async throws -> DNSDoHHTTPResponse {
        requests.append(request)
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
        guard !outcomes.isEmpty else { throw DNSDoHError.transport }
        switch outcomes.removeFirst() {
        case .response(let response):
            return response
        case .error(let error):
            throw error
        }
    }

    func requestSnapshot() -> [DNSDoHRequest] {
        requests
    }
}

@MainActor private final class MappingDoHClient: DNSDoHHTTPClient, @unchecked Sendable {
    private let responses: [Data: Data]
    private var requests: [DNSDoHRequest] = []

    init(responses: [Data: Data]) {
        self.responses = responses
    }

    func send(_ request: DNSDoHRequest) async throws -> DNSDoHHTTPResponse {
        requests.append(request)
        try await Task.sleep(nanoseconds: request.body.first == 0x01 ? 30_000_000 : 1_000_000)
        guard let body = responses[request.body] else { throw DNSDoHError.transport }
        return DNSDoHHTTPResponse(
            statusCode: 200,
            headers: ["Content-Type": "application/dns-message"],
            body: body
        )
    }

    func requestSnapshot() -> [DNSDoHRequest] {
        requests
    }
}

@MainActor
final class DNSDoHTests: XCTestCase {
    func testAllowedQueryUsesDoHPostHeadersAndPreservesWireBody() async throws {
        let query = makeQuery(id: 0x1234, type: 1)
        let response = makeResponse(for: query, flags: 0x8180)
        let client = RecordingDoHClient(outcomes: [
            .response(DNSDoHHTTPResponse(
                statusCode: 200,
                headers: ["Content-Type": "application/dns-message; charset=binary"],
                body: response
            ))
        ])
        let transport = DNSDoHTransport(endpoint: .cloudflare, client: client)

        let result = try await transport.resolve(query)
        XCTAssertEqual(result, response)

        let requests = await client.requestSnapshot()
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.endpoint, .cloudflare)
        XCTAssertEqual(request.body, query)
        XCTAssertEqual(request.headers["Content-Type"], "application/dns-message")
        XCTAssertEqual(request.headers["Accept"], "application/dns-message")
        XCTAssertEqual(request.headers["Host"], "cloudflare-dns.com")

        let encoded = request.encodedHTTPMessage()
        XCTAssertTrue(String(decoding: encoded, as: UTF8.self).hasPrefix("POST /dns-query HTTP/1.1"))
        XCTAssertEqual(Data(encoded.suffix(query.count)), query)
    }

    func testValidAAndAAAAResponsesAreAccepted() async throws {
        for type in [UInt16(1), UInt16(28)] {
            let query = makeQuery(id: type, type: type)
            let response = makeAnswerResponse(for: query, type: type)
            let client = RecordingDoHClient(outcomes: [
                .response(DNSDoHHTTPResponse(
                    statusCode: 200,
                    headers: ["content-type": "application/dns-message"],
                    body: response
                ))
            ])

            let result = try await DNSDoHTransport(endpoint: .cloudflare, client: client).resolve(query)
            XCTAssertEqual(result, response)
        }
    }

    func testNXDOMAINDoesNotTriggerFallback() async throws {
        let query = makeQuery(id: 0x2200, type: 1)
        let primary = RecordingDoHClient(outcomes: [
            .response(DNSDoHHTTPResponse(
                statusCode: 200,
                headers: ["Content-Type": "application/dns-message"],
                body: makeResponse(for: query, flags: 0x8183)
            ))
        ])
        let fallback = RecordingDoHClient(outcomes: [
            .error(.transport)
        ])
        let resolver = DNSUpstreamResolver(
            primary: DNSDoHTransport(endpoint: .cloudflare, client: primary),
            fallback: DNSDoHTransport(endpoint: .quad9, client: fallback)
        )

        let result = try await resolver.resolve(query)

        XCTAssertEqual(result, makeResponse(for: query, flags: 0x8183))
        let primaryRequests = await primary.requestSnapshot()
        let fallbackRequests = await fallback.requestSnapshot()
        XCTAssertEqual(primaryRequests.count, 1)
        XCTAssertTrue(fallbackRequests.isEmpty)
    }

    func testPrimaryTimeoutFallsBackToQuad9() async throws {
        let query = makeQuery(id: 0x3300, type: 1)
        let response = makeResponse(for: query, flags: 0x8180)
        let primary = RecordingDoHClient(outcomes: [.error(.timeout)])
        let fallback = RecordingDoHClient(outcomes: [
            .response(DNSDoHHTTPResponse(
                statusCode: 200,
                headers: ["Content-Type": "application/dns-message"],
                body: response
            ))
        ])

        let result = try await DNSUpstreamResolver(
            primary: DNSDoHTransport(endpoint: .cloudflare, client: primary),
            fallback: DNSDoHTransport(endpoint: .quad9, client: fallback)
        ).resolve(query)

        XCTAssertEqual(result, response)
        let primaryRequests = await primary.requestSnapshot()
        let fallbackRequests = await fallback.requestSnapshot()
        XCTAssertEqual(primaryRequests.count, 1)
        XCTAssertEqual(fallbackRequests.count, 1)
    }

    func testHTTP500EmptyAndInvalidPayloadsFallBack() async throws {
        let query = makeQuery(id: 0x4400, type: 1)
        let validResponse = makeResponse(for: query, flags: 0x8180)
        let invalidPrimaryResponses: [DNSDoHHTTPResponse] = [
            DNSDoHHTTPResponse(statusCode: 500, headers: ["Content-Type": "application/dns-message"], body: validResponse),
            DNSDoHHTTPResponse(statusCode: 200, headers: ["Content-Type": "application/dns-message"], body: Data()),
            DNSDoHHTTPResponse(statusCode: 200, headers: ["Content-Type": "application/dns-message"], body: Data([0x00, 0x01]))
        ]

        for invalidResponse in invalidPrimaryResponses {
            let primary = RecordingDoHClient(outcomes: [.response(invalidResponse)])
            let fallback = RecordingDoHClient(outcomes: [
                .response(DNSDoHHTTPResponse(
                    statusCode: 200,
                    headers: ["Content-Type": "application/dns-message"],
                    body: validResponse
                ))
            ])
            let resolver = DNSUpstreamResolver(
                primary: DNSDoHTransport(endpoint: .cloudflare, client: primary),
                fallback: DNSDoHTransport(endpoint: .quad9, client: fallback)
            )

            let result = try await resolver.resolve(query)
            XCTAssertEqual(result, validResponse)
            let fallbackRequests = await fallback.requestSnapshot()
            XCTAssertEqual(fallbackRequests.count, 1)
        }
    }

    func testBothEncryptedProvidersFailWithoutPlaintextFallback() async throws {
        let query = makeQuery(id: 0x5500, type: 1)
        let primary = RecordingDoHClient(outcomes: [.error(.transport)])
        let fallback = RecordingDoHClient(outcomes: [.error(.timeout)])
        let resolver = DNSUpstreamResolver(
            primary: DNSDoHTransport(endpoint: .cloudflare, client: primary),
            fallback: DNSDoHTransport(endpoint: .quad9, client: fallback)
        )

        do {
            _ = try await resolver.resolve(query)
            XCTFail("Both encrypted resolvers should fail")
        } catch {
            XCTAssertEqual(error as? DNSDoHError, .timeout)
        }

        XCTAssertTrue(DNSDoHEndpoint.cloudflare.addresses.allSatisfy { $0 != "8.8.8.8" })
        XCTAssertTrue(DNSDoHEndpoint.quad9.addresses.allSatisfy { $0 != "8.8.8.8" })
    }

    func testConcurrentQueriesReturnTheirMatchingResponses() async throws {
        let firstQuery = makeQuery(id: 0x0100, type: 1)
        let secondQuery = makeQuery(id: 0x0200, type: 28)
        let firstResponse = makeAnswerResponse(for: firstQuery, type: 1)
        let secondResponse = makeAnswerResponse(for: secondQuery, type: 28)
        let client = MappingDoHClient(responses: [
            firstQuery: firstResponse,
            secondQuery: secondResponse
        ])
        let transport = DNSDoHTransport(endpoint: .cloudflare, client: client)

        async let first = transport.resolve(firstQuery)
        async let second = transport.resolve(secondQuery)
        let results = try await [first, second]

        XCTAssertEqual(results[0], firstResponse)
        XCTAssertEqual(results[1], secondResponse)
        let requests = client.requestSnapshot()
        XCTAssertEqual(requests.count, 2)
    }

    func testCancellationDoesNotStartFallback() async throws {
        let query = makeQuery(id: 0x6600, type: 1)
        let primary = RecordingDoHClient(outcomes: [.error(.timeout)], delayNanoseconds: 10_000_000_000)
        let fallback = RecordingDoHClient(outcomes: [.error(.transport)])
        let resolver = DNSUpstreamResolver(
            primary: DNSDoHTransport(endpoint: .cloudflare, client: primary),
            fallback: DNSDoHTransport(endpoint: .quad9, client: fallback)
        )

        let task = Task {
            try await resolver.resolve(query)
        }
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("The cancelled resolution should not complete")
        } catch is CancellationError {
            // Expected.
        }
        let fallbackRequests = await fallback.requestSnapshot()
        XCTAssertTrue(fallbackRequests.isEmpty)
    }

    func testDoHEndpointsUseHTTPSPathsAndProviderHostnames() {
        XCTAssertEqual(DNSDoHEndpoint.cloudflare.path, "/dns-query")
        XCTAssertEqual(DNSDoHEndpoint.quad9.path, "/dns-query")
        XCTAssertEqual(DNSDoHEndpoint.cloudflare.hostname, "cloudflare-dns.com")
        XCTAssertEqual(DNSDoHEndpoint.quad9.hostname, "dns.quad9.net")
        XCTAssertTrue(DNSDoHEndpoint.cloudflare.addresses.allSatisfy { $0.contains(".") })
        XCTAssertTrue(DNSDoHEndpoint.quad9.addresses.allSatisfy { $0.contains(".") })
    }

    func testDoHProviderBootstrapQueriesAreAnsweredLocallyToPreventRecursion() throws {
        let cloudflareA = makeQuery(id: 0x7700, type: 1, domain: "cloudflare-dns.com")
        let cloudflareResponse = try XCTUnwrap(DNSDoHEndpoint.bootstrapResponse(for: cloudflareA))
        XCTAssertEqual(readUInt16(cloudflareResponse, at: 0), 0x7700)
        XCTAssertEqual(readUInt16(cloudflareResponse, at: 2)! & 0x8000, 0x8000)
        XCTAssertEqual(readUInt16(cloudflareResponse, at: 6), 2)
        XCTAssertEqual(Data(cloudflareResponse.suffix(4)), Data([1, 0, 0, 1]))

        let quad9AAAA = makeQuery(id: 0x7701, type: 28, domain: "dns.quad9.net.")
        let quad9Response = try XCTUnwrap(DNSDoHEndpoint.bootstrapResponse(for: quad9AAAA))
        XCTAssertEqual(readUInt16(quad9Response, at: 2)! & 0x8000, 0x8000)
        XCTAssertEqual(readUInt16(quad9Response, at: 6), 0)

        let unrelated = makeQuery(id: 0x7702, type: 1, domain: "example.com")
        XCTAssertNil(DNSDoHEndpoint.bootstrapResponse(for: unrelated))
    }

    private func makeQuery(id: UInt16, type: UInt16, domain: String = "example.com") -> Data {
        var data = Data()
        append(id, to: &data)
        append(0x0100, to: &data)
        append(1, to: &data)
        append(0, to: &data)
        append(0, to: &data)
        append(0, to: &data)

        for label in domain.split(separator: ".") {
            data.append(UInt8(label.utf8.count))
            data.append(contentsOf: label.utf8)
        }
        data.append(0)
        append(type, to: &data)
        append(1, to: &data)
        return data
    }

    private func makeResponse(for query: Data, flags: UInt16) -> Data {
        var response = query
        response[2] = UInt8(flags >> 8)
        response[3] = UInt8(flags & 0xff)
        return response
    }

    private func makeAnswerResponse(for query: Data, type: UInt16) -> Data {
        var response = makeResponse(for: query, flags: 0x8180)
        response[6] = 0
        response[7] = 1
        response.append(contentsOf: [0xc0, 0x0c])
        append(type, to: &response)
        append(1, to: &response)
        append(60, to: &response)
        append(0, to: &response)

        if type == 1 {
            append(4, to: &response)
            response.append(contentsOf: [1, 2, 3, 4])
        } else {
            append(16, to: &response)
            response.append(contentsOf: Array(repeating: 0, count: 15) + [1])
        }
        return response
    }

    private func append(_ value: UInt16, to data: inout Data) {
        data.append(UInt8(value >> 8))
        data.append(UInt8(value & 0xff))
    }

    private func readUInt16(_ data: Data, at offset: Int) -> UInt16? {
        guard offset >= 0, offset + 2 <= data.count else { return nil }
        return UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
    }
}

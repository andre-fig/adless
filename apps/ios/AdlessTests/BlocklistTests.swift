import Foundation
import CryptoKit
import XCTest
@testable import Adless

private final class StubURLProtocol: URLProtocol {
    enum StubError: Error { case interrupted }
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            guard let handler = Self.handler else { throw StubError.interrupted }
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

@MainActor
final class BlocklistTests: XCTestCase {
    func testCanonicalParsingAndSubdomainMatching() throws {
        let data = Data("ads.example.com\ntracker.example.com\n".utf8)
        let entries = try BlocklistParser.parseCanonical(data)

        XCTAssertEqual(entries.count, 2)
        XCTAssertTrue(BlocklistParser.matches(domain: "cdn.ads.example.com.", entries: entries))
        XCTAssertFalse(BlocklistParser.matches(domain: "ads.example.co", entries: entries))
    }

    func testDomainMatchingUsesBoundedSuffixesAndNormalizesDNSNames() {
        let entries: Set<String> = [
            "ads.example.com",
            "xn--bcher-kva.example"
        ]

        XCTAssertTrue(BlocklistParser.matches(domain: "ADS.EXAMPLE.COM.", entries: entries))
        XCTAssertTrue(BlocklistParser.matches(domain: "cdn.ads.example.com.", entries: entries))
        XCTAssertFalse(BlocklistParser.matches(domain: "ads.example.com.evil", entries: entries))
        XCTAssertTrue(BlocklistParser.matches(domain: "XN--BCHER-KVA.EXAMPLE.", entries: entries))
        XCTAssertFalse(BlocklistParser.matches(domain: "bücher.example.", entries: entries))
    }

    func testCanonicalParserRejectsUnsortedAndInvalidContent() {
        XCTAssertThrowsError(try BlocklistParser.parseCanonical(Data("z.example.com\na.example.com\n".utf8)))
        XCTAssertThrowsError(try BlocklistParser.parseCanonical(Data("<html>blocked</html>\n".utf8)))
        XCTAssertThrowsError(try BlocklistParser.parseCanonical(Data("ads.example.com".utf8)))
    }

    func testGzipDecoderValidatesPayloadAndChecksum() throws {
        let encoded = "H4sIAAAAAAAC/0tMKdZLrUjMLchJ1UvOz+UqKUpMzk4tQhEDABIGOqIkAAAA"
        let compressed = try XCTUnwrap(Data(base64Encoded: encoded))
        let decoded = try GzipDecoder.decode(compressed, expectedSize: 36, maximumSize: 1024)
        XCTAssertEqual(String(data: decoded, encoding: .utf8), "ads.example.com\ntracker.example.com\n")

        var corrupted = compressed
        corrupted[corrupted.index(before: corrupted.endIndex)] ^= 0xff
        XCTAssertThrowsError(try GzipDecoder.decode(corrupted, expectedSize: 36, maximumSize: 1024))
    }

    func testSuccessfulUpdateAndManifestWithoutContentChange() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = BlocklistStorage(embeddedSeedData: Data("seed.example.com\n".utf8), baseDirectory: directory)
        _ = try storage.ensureEmbeddedSeed()

        let canonical = Data("ads.example.com\ntracker.example.com\n".utf8)
        let compressed = try XCTUnwrap(Data(base64Encoded: "H4sIAAAAAAAC/0tMKdZLrUjMLchJ1UvOz+UqKUpMzk4tQhEDABIGOqIkAAAA"))
        let hash = SHA256.hash(data: compressed).compactMap { String(format: "%02x", $0) }.joined()
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let manifest = """
        {"schemaVersion":1,"version":"v1111111111111111","generatedAt":"\(timestamp)","file":"blocklist.txt.gz","downloadUrl":"blocklist.txt.gz","compression":"gzip","sha256":"\(hash)","sizeBytes":\(compressed.count),"uncompressedSizeBytes":\(canonical.count),"domainCount":2,"sources":[{"id":"fixture","name":"Fixture"}]}
        """.data(using: .utf8)!

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        StubURLProtocol.handler = { request in
            let path = request.url?.path ?? ""
            let body = path.hasSuffix("manifest.json") ? manifest : compressed
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["ETag": "fixture-v1"])!, body)
        }
        defer { StubURLProtocol.handler = nil }

        let session = URLSession(configuration: configuration)
        let service = BlocklistUpdateService(session: session, storage: storage)
        let firstResult = try await service.refreshIfNeeded(force: true)
        XCTAssertEqual(firstResult, .updated(version: "v1111111111111111"))
        XCTAssertEqual(try storage.loadActive(), ["ads.example.com", "tracker.example.com"])
        let secondResult = try await service.refreshIfNeeded(force: true)
        XCTAssertEqual(secondResult, .notModified)
    }

    func testChecksumFailureAndInterruptedDownloadPreserveLastValidList() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = BlocklistStorage(embeddedSeedData: Data("seed.example.com\n".utf8), baseDirectory: directory)
        _ = try storage.ensureEmbeddedSeed()
        let validCompressed = try XCTUnwrap(Data(base64Encoded: "H4sIAAAAAAAC/0tMKdZLrUjMLchJ1UvOz+UqKUpMzk4tQhEDABIGOqIkAAAA"))
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let manifest = """
        {"schemaVersion":1,"version":"v2222222222222222","generatedAt":"\(timestamp)","file":"blocklist.txt.gz","downloadUrl":"blocklist.txt.gz","compression":"gzip","sha256":"\(String(repeating: "0", count: 64))","sizeBytes":\(validCompressed.count),"uncompressedSizeBytes":36,"domainCount":2,"sources":[]}
        """.data(using: .utf8)!

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        StubURLProtocol.handler = { request in
            if request.url?.path.hasSuffix("manifest.json") == true {
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, manifest)
            }
            throw StubURLProtocol.StubError.interrupted
        }
        defer { StubURLProtocol.handler = nil }

        let service = BlocklistUpdateService(session: URLSession(configuration: configuration), storage: storage)
        do {
            _ = try await service.refreshIfNeeded(force: true)
            XCTFail("The interrupted download should fail")
        } catch {
            // Expected: the previous embedded list must remain active.
        }
        XCTAssertEqual(try storage.loadActive(), ["seed.example.com"])
    }

    func testSubscriptionAccessPolicyAllowsActiveAndGracePeriodUntilExpiry() {
        let now = Date(timeIntervalSince1970: 10_000)
        let active = SubscriptionAccessSnapshot(
            isEntitled: true,
            productID: "com.orbeworks.adless.pro.monthly",
            effectiveUntil: now.addingTimeInterval(60),
            inGracePeriod: false,
            lastVerifiedAt: now
        )
        let grace = SubscriptionAccessSnapshot(
            isEntitled: true,
            productID: "com.orbeworks.adless.pro.monthly",
            effectiveUntil: now.addingTimeInterval(60),
            inGracePeriod: true,
            lastVerifiedAt: now
        )

        XCTAssertTrue(SubscriptionAccessPolicy.allowsAccess(active, at: now))
        XCTAssertTrue(SubscriptionAccessPolicy.allowsAccess(grace, at: now))
        XCTAssertFalse(SubscriptionAccessPolicy.allowsAccess(active, at: now.addingTimeInterval(60)))
        XCTAssertFalse(SubscriptionAccessPolicy.allowsAccess(.inactive(at: now), at: now))
    }

    func testSubscriptionStorageRoundTripsAppGroupSnapshotAtomically() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = SubscriptionStorage(baseDirectory: directory)
        let now = Date(timeIntervalSince1970: 20_000)
        let snapshot = SubscriptionAccessSnapshot(
            isEntitled: true,
            productID: "com.orbeworks.adless.pro.yearly",
            effectiveUntil: now.addingTimeInterval(3600),
            inGracePeriod: false,
            lastVerifiedAt: now
        )

        try storage.save(snapshot)

        XCTAssertEqual(storage.load(), snapshot)
    }
}

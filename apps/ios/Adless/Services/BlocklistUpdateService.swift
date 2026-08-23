import CryptoKit
import Foundation
import os.log

enum BlocklistRefreshResult: Equatable {
    case skipped
    case notModified
    case updated(version: String)
}

final class BlocklistUpdateService {
    private let session: URLSession
    private let storage: BlocklistStorage
    private let now: () -> Date

    init(session: URLSession = .shared, storage: BlocklistStorage = BlocklistStorage(), now: @escaping () -> Date = Date.init) {
        self.session = session
        self.storage = storage
        self.now = now
    }

    func refreshIfNeeded(force: Bool = false) async throws -> BlocklistRefreshResult {
        var state = storage.updateState()
        let currentDate = now()
        if !force, let lastCheckAt = state.lastCheckAt, currentDate.timeIntervalSince(lastCheckAt) < BlocklistConfiguration.refreshInterval {
            return .skipped
        }
        if !force, let nextRetryAt = state.nextRetryAt, currentDate < nextRetryAt {
            return .skipped
        }

        do {
            let (manifest, response) = try await fetchManifest(state: state)
            if response.statusCode == 304 {
                guard storage.hasValidActive(), storage.storedManifest() != nil else {
                    throw BlocklistUpdateError.notModifiedWithoutValidCache
                }
                state.lastCheckAt = currentDate
                state.nextRetryAt = nil
                state.failureCount = 0
                updateCachingHeaders(response: response, state: &state)
                try storage.saveUpdateState(state)
                return .notModified
            }

            try manifest.validate()
            guard let downloadURL = URL(string: manifest.downloadUrl, relativeTo: BlocklistConfiguration.manifestURL)?.absoluteURL,
                  isAllowedURL(downloadURL) else { throw BlocklistUpdateError.insecureURL }

            if storage.hasValidActive(),
               let installed = storage.storedManifest(),
               installed.version == manifest.version,
               installed.sha256 == manifest.sha256 {
                state.lastCheckAt = currentDate
                state.nextRetryAt = nil
                state.failureCount = 0
                state.manifestVersion = manifest.version
                state.manifestSHA256 = manifest.sha256
                updateCachingHeaders(response: response, state: &state)
                try storage.saveUpdateState(state)
                return .notModified
            }

            let compressed = try await fetchPayload(from: downloadURL, expectedSize: manifest.sizeBytes)
            let digest = SHA256.hash(data: compressed).compactMap { String(format: "%02x", $0) }.joined()
            guard digest == manifest.sha256 else { throw BlocklistUpdateError.checksumMismatch }
            let canonical = try GzipDecoder.decode(
                compressed,
                expectedSize: manifest.uncompressedSizeBytes,
                maximumSize: BlocklistConfiguration.maximumPayloadBytes
            )
            let entries = try BlocklistParser.parseCanonical(canonical)
            guard entries.count == manifest.domainCount else { throw BlocklistUpdateError.countMismatch }

            let manifestData = try JSONEncoder().encode(manifest)
            try storage.install(canonical: canonical, compressed: compressed, manifest: manifestData)
            state.lastCheckAt = currentDate
            state.nextRetryAt = nil
            state.failureCount = 0
            state.manifestVersion = manifest.version
            state.manifestSHA256 = manifest.sha256
            updateCachingHeaders(response: response, state: &state)
            try storage.saveUpdateState(state)
            return .updated(version: manifest.version)
        } catch {
            state.failureCount += 1
            let delay = min(pow(2.0, Double(max(state.failureCount - 1, 0))) * 15 * 60, 24 * 60 * 60)
            state.nextRetryAt = currentDate.addingTimeInterval(delay)
            try? storage.saveUpdateState(state)
            AdlessSentry.capture(error, operation: "blocklist.refresh")
            os_log("Blocklist refresh failed: %{public}@", log: .default, type: .error, error.localizedDescription)
            throw error
        }
    }

    private func fetchManifest(state: BlocklistUpdateState) async throws -> (BlocklistManifest, HTTPURLResponse) {
        var request = URLRequest(url: BlocklistConfiguration.manifestURL)
        request.cachePolicy = .reloadRevalidatingCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let etag = state.etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        if let lastModified = state.lastModified { request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since") }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              isAllowedURL(http.url),
              http.statusCode == 200 || http.statusCode == 304 else { throw BlocklistUpdateError.invalidResponse }
        guard data.count <= BlocklistConfiguration.maximumManifestBytes else { throw BlocklistUpdateError.payloadTooLarge }
        if http.statusCode == 304 {
            return (BlocklistManifest.placeholder, http)
        }
        let manifest = try JSONDecoder().decode(BlocklistManifest.self, from: data)
        return (manifest, http)
    }

    private func fetchPayload(from url: URL, expectedSize: Int) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("application/gzip", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              isAllowedURL(http.url),
              http.statusCode == 200 else { throw BlocklistUpdateError.invalidResponse }
        guard expectedSize > 0, data.count == expectedSize, data.count <= BlocklistConfiguration.maximumPayloadBytes else {
            throw BlocklistUpdateError.payloadTooLarge
        }
        return data
    }

    private func updateCachingHeaders(response: HTTPURLResponse, state: inout BlocklistUpdateState) {
        state.etag = response.value(forHTTPHeaderField: "ETag") ?? state.etag
        state.lastModified = response.value(forHTTPHeaderField: "Last-Modified") ?? state.lastModified
    }

    private func isAllowedURL(_ url: URL?) -> Bool {
        guard let url else { return false }
        return url.scheme?.lowercased() == "https" && url.host?.lowercased() == BlocklistConfiguration.manifestURL.host?.lowercased()
    }
}

private extension BlocklistManifest {
    static let placeholder = BlocklistManifest(
        schemaVersion: 1,
        version: "v0000000000000000",
        generatedAt: "1970-01-01T00:00:00Z",
        file: "blocklist.txt.gz",
        downloadUrl: "blocklist.txt.gz",
        compression: "gzip",
        sha256: String(repeating: "0", count: 64),
        sizeBytes: 1,
        uncompressedSizeBytes: 1,
        domainCount: 1,
        sources: []
    )
}

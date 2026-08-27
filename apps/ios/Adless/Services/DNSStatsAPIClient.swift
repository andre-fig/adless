import Foundation

struct DNSStatsResponse: Decodable, Equatable {
    let blockedTotal: Int
    let updatedAt: String
}

enum DNSStatsAPIError: LocalizedError {
    case invalidResponse
    case invalidPayload

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The blocking statistics service returned an invalid response"
        case .invalidPayload:
            return "The blocking statistics payload is invalid"
        }
    }
}

final class DNSStatsAPIClient: @unchecked Sendable {
    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.urlCache = nil
            configuration.httpCookieStorage = nil
            configuration.urlCredentialStorage = nil
            configuration.httpShouldSetCookies = false
            configuration.waitsForConnectivity = false
            configuration.timeoutIntervalForRequest = 4
            configuration.timeoutIntervalForResource = 4
            self.session = URLSession(configuration: configuration)
        }
    }

    deinit {
        session.invalidateAndCancel()
    }

    func fetchBlockedTotal() async throws -> Int {
        let token = try InstallationTokenStore.shared.token()
        var request = URLRequest(url: DNSCloudConfiguration.statsURL)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              data.count <= 4 * 1024 else {
            throw DNSStatsAPIError.invalidResponse
        }

        let payload = try JSONDecoder().decode(DNSStatsResponse.self, from: data)
        guard payload.blockedTotal >= 0, !payload.updatedAt.isEmpty else {
            throw DNSStatsAPIError.invalidPayload
        }
        return payload.blockedTotal
    }
}

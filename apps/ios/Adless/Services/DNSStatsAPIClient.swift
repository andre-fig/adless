import Foundation

struct DNSStatsResponse: Decodable, Equatable {
    let blockedTotal: Int
    let updatedAt: String
}

enum DNSStatsAPIError: LocalizedError {
    case invalidResponse
    case invalidPayload
    case authorizationRequired

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The blocking statistics service returned an invalid response"
        case .invalidPayload:
            return "The blocking statistics payload is invalid"
        case .authorizationRequired:
            return "Subscription authorization is required"
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
        let token: String
        do {
            token = try InstallationTokenStore.shared.statsToken()
        } catch {
            throw DNSStatsAPIError.authorizationRequired
        }
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

private struct DNSAuthorizationRequest: Encodable {
    let installationId: String
    let transactionJWS: String
}

private struct DNSAuthorizationResponse: Decodable {
    let installationId: String
    let dnsToken: String
    let statsToken: String
}

enum DNSAuthorizationAPIError: LocalizedError {
    case invalidResponse
    case transactionNotAuthorized

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The authorization service returned an invalid response"
        case .transactionNotAuthorized:
            return "The subscription could not be authorized"
        }
    }
}

final class DNSAuthorizationAPIClient: @unchecked Sendable {
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
            configuration.timeoutIntervalForRequest = 8
            configuration.timeoutIntervalForResource = 8
            self.session = URLSession(configuration: configuration)
        }
    }

    deinit {
        session.invalidateAndCancel()
    }

    func authorize(transactionJWS: String, installationId: String) async throws -> InstallationCredentials {
        guard UUID(uuidString: installationId) != nil,
              !transactionJWS.isEmpty,
              transactionJWS.utf8.count <= 128 * 1024 else {
            throw DNSAuthorizationAPIError.invalidResponse
        }

        var request = URLRequest(url: DNSCloudConfiguration.authorizationURL)
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(
            DNSAuthorizationRequest(installationId: installationId, transactionJWS: transactionJWS)
        )

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw DNSAuthorizationAPIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode), data.count <= 16 * 1024 else {
            if http.statusCode == 401 { throw DNSAuthorizationAPIError.transactionNotAuthorized }
            throw DNSAuthorizationAPIError.invalidResponse
        }

        let payload: DNSAuthorizationResponse
        do {
            payload = try JSONDecoder().decode(DNSAuthorizationResponse.self, from: data)
        } catch {
            throw DNSAuthorizationAPIError.invalidResponse
        }
        guard payload.installationId == installationId,
              InstallationTokenStore.isValid(payload.dnsToken),
              InstallationTokenStore.isValid(payload.statsToken),
              payload.dnsToken != payload.statsToken else {
            throw DNSAuthorizationAPIError.invalidResponse
        }
        return InstallationCredentials(
            installationId: payload.installationId,
            dnsToken: payload.dnsToken,
            statsToken: payload.statsToken
        )
    }
}

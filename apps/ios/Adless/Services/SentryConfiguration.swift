import Foundation
import Sentry

enum AdlessSentry {
    nonisolated private static let dsn = "https://2f1865aead67f3607d25bb035692fad2@o4511935178080256.ingest.us.sentry.io/4511957005697024"

    nonisolated static func shouldStart(environment: [String: String]) -> Bool {
        environment["XCTestConfigurationFilePath"] == nil
            && environment["XCTestBundlePath"] == nil
    }

    nonisolated static func start() {
        guard shouldStart(environment: ProcessInfo.processInfo.environment) else { return }
        SentrySDK.start { options in
            options.dsn = dsn
#if DEBUG
            options.environment = "development"
#else
            options.environment = "production"
#endif
            options.sendDefaultPii = false
            options.tracesSampleRate = 0.1
            options.enableNetworkTracking = false
            options.enableNetworkBreadcrumbs = false
            options.enableCaptureFailedRequests = false
            options.enableAutoBreadcrumbTracking = false
            options.attachScreenshot = false
            options.attachViewHierarchy = false
            options.enableUserInteractionTracing = false
        }
    }

    nonisolated static func event(_ operation: String, state: String? = nil) {
        guard SentrySDK.isEnabled else { return }
        SentrySDK.capture(message: operation) { scope in
            scope.setTag(value: operation, key: "operation")
            scope.setTag(value: state ?? "unknown", key: "dns_status")
        }
    }

    nonisolated static func capture(_ error: Error, operation: String, state: String? = nil) {
        guard SentrySDK.isEnabled else { return }
        let nsError = error as NSError
        let description = sanitizedDescription(nsError.localizedDescription)
        let sanitizedError = NSError(
            domain: nsError.domain,
            code: nsError.code,
            userInfo: [NSLocalizedDescriptionKey: description]
        )
        SentrySDK.capture(error: sanitizedError) { scope in
            scope.setTag(value: operation, key: "operation")
            scope.setTag(value: nsError.domain, key: "error_domain")
            scope.setTag(value: String(nsError.code), key: "error_code")
            scope.setTag(value: description, key: "error_description")
            scope.setTag(value: state ?? "unknown", key: "dns_status")
        }
    }

    nonisolated static func startTransaction(name: String, operation: String) -> Span? {
        guard SentrySDK.isEnabled else { return nil }
        return SentrySDK.startTransaction(name: name, operation: operation)
    }

    nonisolated private static func sanitizedDescription(_ value: String) -> String {
        value
            .replacingOccurrences(
                of: #"https?://[^\s\"<>]+"#,
                with: "<redacted-url>",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"(?i)(?:[a-z0-9-]+\.)+[a-z]{2,63}"#,
                with: "<redacted-host>",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"(?:[0-9]{1,3}\.){3}[0-9]{1,3}"#,
                with: "<redacted-ip>",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"(?i)(?:[0-9a-f]{1,4}:){2,}[0-9a-f:]{1,4}"#,
                with: "<redacted-ip>",
                options: .regularExpression
            )
    }
}

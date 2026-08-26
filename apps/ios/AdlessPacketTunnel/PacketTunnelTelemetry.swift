import Foundation
import NetworkExtension
import Sentry
import os

enum PacketTunnelTelemetry {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "AdlessPacketTunnel",
        category: "tunnel"
    )
    private static let dsn = "https://2f1865aead67f3607d25bb035692fad2@o4511935178080256.ingest.us.sentry.io/4511957005697024"

    static func start() {
        SentrySDK.start { options in
            options.dsn = dsn
#if DEBUG
            options.environment = "development"
#else
            options.environment = "production"
#endif
            options.sendDefaultPii = false
            options.enableNetworkTracking = false
            options.enableNetworkBreadcrumbs = false
            options.enableCaptureFailedRequests = false
            options.enableAutoBreadcrumbTracking = false
            options.attachScreenshot = false
            options.attachViewHierarchy = false
            options.enableUserInteractionTracing = false
            options.tracesSampleRate = 0.1
        }
    }

    static func event(_ operation: String, status: NEVPNStatus? = nil) {
        let statusValue = status.map(statusName) ?? "unknown"
        logger.debug("(operation, privacy: .public) status=(statusValue, privacy: .public)")
        guard SentrySDK.isEnabled else { return }
        SentrySDK.capture(message: operation) { scope in
            scope.setTag(value: operation, key: "operation")
            scope.setTag(value: statusValue, key: "vpn_status")
        }
    }

    static func error(_ error: Error, operation: String, status: NEVPNStatus? = nil) {
        let nsError = error as NSError
        let description = sanitizedDescription(nsError.localizedDescription)
        let statusValue = status.map(statusName) ?? "unknown"
        logger.error("(operation, privacy: .public) domain=(nsError.domain, privacy: .public) code=(nsError.code, privacy: .public) description=(description, privacy: .public) status=(statusValue, privacy: .public)")
        guard SentrySDK.isEnabled else { return }

        // Capture a sanitized event instead of the original NSError. URL
        // loading errors can contain a provider URL, which must never leave
        // the extension as diagnostic data.
        let sanitized = NSError(
            domain: nsError.domain,
            code: nsError.code,
            userInfo: [NSLocalizedDescriptionKey: description]
        )
        SentrySDK.capture(error: sanitized) { scope in
            scope.setTag(value: operation, key: "operation")
            scope.setTag(value: nsError.domain, key: "error_domain")
            scope.setTag(value: String(nsError.code), key: "error_code")
            scope.setTag(value: description, key: "error_description")
            scope.setTag(value: statusValue, key: "vpn_status")
        }
    }

    private static func statusName(_ status: NEVPNStatus) -> String {
        switch status {
        case .invalid: return "invalid"
        case .disconnected: return "disconnected"
        case .connecting: return "connecting"
        case .connected: return "connected"
        case .reasserting: return "reasserting"
        case .disconnecting: return "disconnecting"
        @unknown default: return "unknown"
        }
    }

    private static func sanitizedDescription(_ value: String) -> String {
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

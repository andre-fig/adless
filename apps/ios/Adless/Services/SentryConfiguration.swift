import Foundation
import Sentry

enum AdlessSentry {
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

    static func capture(_ error: Error, operation: String) {
        guard SentrySDK.isEnabled else { return }
        SentrySDK.capture(error: error) { scope in
            scope.setTag(value: operation, key: "operation")
        }
    }

    static func startTransaction(name: String, operation: String) -> Span? {
        guard SentrySDK.isEnabled else { return nil }
        return SentrySDK.startTransaction(name: name, operation: operation)
    }
}

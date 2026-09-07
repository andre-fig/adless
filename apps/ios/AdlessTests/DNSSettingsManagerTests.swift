import Foundation
@preconcurrency import NetworkExtension
import XCTest
@testable import Adless

@MainActor
final class DNSSettingsManagerTests: XCTestCase {
    func testFailedInstallReloadsPreviouslyEnabledConfiguration() async throws {
        let oldToken = String(repeating: "A", count: 43)
        let newToken = String(repeating: "B", count: 43)
        let oldSettings = NEDNSOverHTTPSSettings(servers: [])
        oldSettings.serverURL = try DNSCloudConfiguration.endpointURL(for: oldToken)
        oldSettings.matchDomains = [""]

        let preferences = DNSSettingsPreferencesStub(
            persistedSettings: oldSettings,
            persistedIsEnabled: true,
            saveError: DNSSettingsPreferencesStub.SaveFailure()
        )
        let manager = DNSSettingsManager(
            systemManager: preferences,
            endpointProvider: { try DNSCloudConfiguration.endpointURL(for: newToken) }
        )

        do {
            _ = try await manager.install()
            XCTFail("Expected the system preference save to fail")
        } catch is DNSSettingsPreferencesStub.SaveFailure {
            // Expected. `install()` must already have reloaded preferences at
            // this point, before the view model handles the error.
        }

        XCTAssertEqual(preferences.loadCallCount, 2)
        XCTAssertEqual(
            (preferences.dnsSettings as? NEDNSOverHTTPSSettings)?.serverURL,
            oldSettings.serverURL
        )
        XCTAssertTrue(preferences.isEnabled)
        let reloadedState = await manager.currentState()
        XCTAssertEqual(reloadedState, .staleEnabled)
        XCTAssertTrue(reloadedState.isSystemEnabled, "the old profile remains enabled in the real system state")
        XCTAssertFalse(AppViewModel.protectionIsConfirmed(
            hasAccess: true,
            hasCredentials: true,
            authorizationRequired: false,
            remoteBlockingState: .enabled,
            dnsState: reloadedState
        ), "an enabled profile with the superseded token is pass-through, not confirmed protection")
    }

    func testEnabledConfigurationRequiresTheCurrentCredentialEndpoint() async throws {
        let currentToken = String(repeating: "B", count: 43)
        let currentSettings = NEDNSOverHTTPSSettings(servers: [])
        currentSettings.serverURL = try DNSCloudConfiguration.endpointURL(for: currentToken)
        currentSettings.matchDomains = [""]
        currentSettings.matchDomainsNoSearch = true

        let preferences = DNSSettingsPreferencesStub(
            persistedSettings: currentSettings,
            persistedIsEnabled: true
        )
        let manager = DNSSettingsManager(
            systemManager: preferences,
            endpointProvider: { try DNSCloudConfiguration.endpointURL(for: currentToken) }
        )

        let state = await manager.currentState()
        XCTAssertEqual(state, .enabled)
        XCTAssertTrue(state.isSystemEnabled)
        XCTAssertTrue(AppViewModel.protectionIsConfirmed(
            hasAccess: true,
            hasCredentials: true,
            authorizationRequired: false,
            remoteBlockingState: .enabled,
            dnsState: state
        ))
    }
}

private final class DNSSettingsPreferencesStub: DNSSettingsPreferencesManaging, @unchecked Sendable {
    struct SaveFailure: Error {}

    var localizedDescription: String?
    var dnsSettings: NEDNSSettings?
    var onDemandRules: [NEOnDemandRule]?
    private(set) var isEnabled = false
    private(set) var loadCallCount = 0

    private var persistedSettings: NEDNSSettings?
    private var persistedIsEnabled: Bool
    private let saveError: Error?

    init(
        persistedSettings: NEDNSSettings?,
        persistedIsEnabled: Bool,
        saveError: Error? = nil
    ) {
        self.persistedSettings = persistedSettings
        self.persistedIsEnabled = persistedIsEnabled
        self.saveError = saveError
    }

    func loadFromPreferences(completionHandler: @escaping @Sendable (Error?) -> Void) {
        loadCallCount += 1
        dnsSettings = persistedSettings
        isEnabled = persistedIsEnabled
        completionHandler(nil)
    }

    func saveToPreferences(completionHandler: @escaping @Sendable (Error?) -> Void) {
        guard saveError == nil else {
            completionHandler(saveError)
            return
        }
        persistedSettings = dnsSettings
        completionHandler(nil)
    }

    func removeFromPreferences(completionHandler: @escaping @Sendable (Error?) -> Void) {
        persistedSettings = nil
        persistedIsEnabled = false
        completionHandler(nil)
    }
}

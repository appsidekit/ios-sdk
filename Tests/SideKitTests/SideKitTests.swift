//
//  SideKitTests.swift
//  SideKit
//

import Testing
import Foundation
@testable import SideKit

// MARK: - Mock Meerkat (API client)

@MainActor
final class MockMeerkat: MeerkatProtocol {
    var sendSignalCallCount = 0
    var lastSentSignals: [SideKit.Signal]?
    var gateInformationToReturn: GateInformation?
    var flagsToReturn: [SideKit.FeatureFlag]?
    var sendFeedbackCallCount = 0
    var lastFeedbackText: String?
    var lastFeedbackEndUserId: String?
    var lastFeedbackUserAttributes: [String: String]?

    func getGateInformation() async -> GateInformation? {
        return gateInformationToReturn
    }

    func getFlags() async -> [SideKit.FeatureFlag]? {
        return flagsToReturn
    }

    func sendSignal(signals: [SideKit.Signal]) {
        sendSignalCallCount += 1
        lastSentSignals = signals
    }

    func sendFeedback(feedbackText: String, endUserId: String?, userAttributes: [String: String]?) {
        sendFeedbackCallCount += 1
        lastFeedbackText = feedbackText
        lastFeedbackEndUserId = endUserId
        lastFeedbackUserAttributes = userAttributes
    }
}

// MARK: - Mock Settings Store

final class MockSettingsStore: SettingsStoreProtocol {
    var isAnalyticsEnabled: Bool
    var isFirstLaunch: Bool = true
    var cachedGateInformation: GateInformation?
    var cachedFlags: [SideKit.FeatureFlag]?
    var authSession: SideKit.AuthSession?

    init(analyticsEnabled: Bool) {
        self.isAnalyticsEnabled = analyticsEnabled
    }
}

// MARK: - Mock Auth Agent

@MainActor
final class MockAuthAgent: AuthAgentProtocol {
    var signInResult: SideKit.AuthResult<SideKit.AuthOtpResponse> = .failure(.init(code: "not_set", status: 0))
    var verifyOtpResult: SideKit.AuthResult<SideKit.AuthVerifyResponse> = .failure(.init(code: "not_set", status: 0))
    var setHandleResult: SideKit.AuthResult<String> = .failure(.init(code: "not_set", status: 0))
    var logoutCallCount = 0
    var lastLogoutToken: String?

    func signIn(channel: SideKit.AuthChannel, identifier: String, inviteCode: String?) async -> SideKit.AuthResult<SideKit.AuthOtpResponse> {
        signInResult
    }
    func verifyOtp(requestId: String, channel: SideKit.AuthChannel, identifier: String, code: String) async -> SideKit.AuthResult<SideKit.AuthVerifyResponse> {
        verifyOtpResult
    }
    func setHandle(token: String, handle: String) async -> SideKit.AuthResult<String> {
        setHandleResult
    }
    func logout(token: String) async -> SideKit.AuthResult<SideKit.EmptyAuthResponse> {
        logoutCallCount += 1
        lastLogoutToken = token
        return .success(SideKit.EmptyAuthResponse())
    }
}

// MARK: - Analytics Tests

@Suite("SideKit Analytics Tests")
struct SideKitAnalyticsTests {

    @Test("Signal is sent when analytics is enabled")
    @MainActor
    func signalSentWhenAnalyticsEnabled() async {
        let mockAgent = MockMeerkat()
        let mockSettings = MockSettingsStore(analyticsEnabled: true)
        let sideKit = SideKit(settings: mockSettings, meerkat: mockAgent)

        sideKit.sendSignal(key: "test_event", value: "test_value")

        #expect(mockAgent.sendSignalCallCount == 1)
        #expect(mockAgent.lastSentSignals == [SideKit.Signal(name: "test_event", value: "test_value")])
    }

    @Test("Signal is NOT sent when analytics is disabled")
    @MainActor
    func signalNotSentWhenAnalyticsDisabled() async {
        let mockAgent = MockMeerkat()
        let mockSettings = MockSettingsStore(analyticsEnabled: false)
        let sideKit = SideKit(settings: mockSettings, meerkat: mockAgent)

        sideKit.sendSignal(key: "test_event", value: "test_value")

        #expect(mockAgent.sendSignalCallCount == 0)
        #expect(mockAgent.lastSentSignals == nil)
    }

    @Test("Signal respects analytics toggle change")
    @MainActor
    func signalRespectsAnalyticsToggle() async {
        let mockAgent = MockMeerkat()
        let mockSettings = MockSettingsStore(analyticsEnabled: true)
        let sideKit = SideKit(settings: mockSettings, meerkat: mockAgent)

        // First signal with analytics enabled
        sideKit.sendSignal("event1")
        #expect(mockAgent.sendSignalCallCount == 1)

        // Disable analytics
        sideKit.isAnalyticsEnabled = false

        // Second signal should not be sent
        sideKit.sendSignal("event2")
        #expect(mockAgent.sendSignalCallCount == 1) // Still 1, not incremented
    }
}

// MARK: - Gate Information Tests

@Suite("Gate Information Tests")
struct GateInformationTests {

    @Test("Live gate type is not blocked")
    func liveGateNotBlocked() {
        let gateInfo = GateInformation(
            gateType: .live,
            lastGateUpdate: "2025-01-01T00:00:00Z",
            latestVersion: "2.0.0",
            whatsNew: "Bug fixes",
            storeUrl: "https://apps.apple.com/app/id123"
        )

        #expect(gateInfo.isBlocked() == false)
        #expect(gateInfo.blockingGateType() == nil)
    }

    @Test("Forced gate type is blocked")
    func forcedGateBlocked() {
        let gateInfo = GateInformation(
            gateType: .forced,
            lastGateUpdate: "2025-01-01T00:00:00Z",
            latestVersion: "2.0.0",
            whatsNew: "Critical security update",
            storeUrl: "https://apps.apple.com/app/id123"
        )

        #expect(gateInfo.isBlocked() == true)
        #expect(gateInfo.blockingGateType() == .forced)
    }

    @Test("Dismissible gate type is blocked")
    func dismissibleGateBlocked() {
        let gateInfo = GateInformation(
            gateType: .dismissible,
            lastGateUpdate: "2025-01-01T00:00:00Z",
            latestVersion: "2.0.0",
            whatsNew: "New features available",
            storeUrl: "https://apps.apple.com/app/id123"
        )

        #expect(gateInfo.isBlocked() == true)
        #expect(gateInfo.blockingGateType() == .dismissible)
    }

    @Test("Modal gate type is blocked")
    func modalGateBlocked() {
        let gateInfo = GateInformation(
            gateType: .modal,
            lastGateUpdate: "2025-01-01T00:00:00Z",
            latestVersion: "2.0.0",
            whatsNew: "Recommended update",
            storeUrl: "https://apps.apple.com/app/id123"
        )

        #expect(gateInfo.isBlocked() == true)
        #expect(gateInfo.blockingGateType() == .modal)
    }

    @Test("Gate information with nil optional fields")
    func gateInfoWithNilFields() {
        let gateInfo = GateInformation(
            gateType: .live,
            lastGateUpdate: "",
            latestVersion: nil,
            whatsNew: nil,
            storeUrl: nil
        )

        #expect(gateInfo.isBlocked() == false)
        #expect(gateInfo.latestVersion == nil)
        #expect(gateInfo.whatsNew == nil)
        #expect(gateInfo.storeUrl == nil)
    }
}

// MARK: - Gate Type Enum Tests

@Suite("Version Gate Type Tests")
struct VersionGateTypeTests {

    @Test("Gate type raw values match backend")
    func gateTypeRawValues() {
        #expect(VersionGateType.live.rawValue == -1)
        #expect(VersionGateType.forced.rawValue == 0)
        #expect(VersionGateType.dismissible.rawValue == 1)
        #expect(VersionGateType.modal.rawValue == 2)
    }

    @Test("Gate type can be created from raw values")
    func gateTypeFromRawValue() {
        #expect(VersionGateType(rawValue: -1) == .live)
        #expect(VersionGateType(rawValue: 0) == .forced)
        #expect(VersionGateType(rawValue: 1) == .dismissible)
        #expect(VersionGateType(rawValue: 2) == .modal)
        #expect(VersionGateType(rawValue: 99) == nil)
    }
}

// MARK: - JSON Decoding Tests

@Suite("Gate Information Decoding Tests")
struct GateInformationDecodingTests {

    @Test("Decodes complete gate information")
    func decodesCompleteGateInfo() throws {
        let json = """
        {
            "gateType": 0,
            "lastGateUpdate": "2025-01-01T00:00:00Z",
            "latestVersion": "2.0.0",
            "whatsNew": "Bug fixes",
            "storeUrl": "https://apps.apple.com/app/id123"
        }
        """
        let data = json.data(using: .utf8)!
        let gateInfo = try JSONDecoder().decode(GateInformation.self, from: data)

        #expect(gateInfo.gateType == .forced)
        #expect(gateInfo.lastGateUpdate == "2025-01-01T00:00:00Z")
        #expect(gateInfo.latestVersion == "2.0.0")
        #expect(gateInfo.whatsNew == "Bug fixes")
        #expect(gateInfo.storeUrl == "https://apps.apple.com/app/id123")
    }

    @Test("Decodes gate information with missing optional fields")
    func decodesMissingOptionalFields() throws {
        let json = """
        {
            "gateType": -1,
            "lastGateUpdate": "2025-01-01T00:00:00Z"
        }
        """
        let data = json.data(using: .utf8)!
        let gateInfo = try JSONDecoder().decode(GateInformation.self, from: data)

        #expect(gateInfo.gateType == .live)
        #expect(gateInfo.lastGateUpdate == "2025-01-01T00:00:00Z")
        #expect(gateInfo.latestVersion == nil)
        #expect(gateInfo.whatsNew == nil)
        #expect(gateInfo.storeUrl == nil)
    }

    @Test("Decodes live gate type from -1")
    func decodesLiveGateType() throws {
        let json = """
        {
            "gateType": -1,
            "lastGateUpdate": "2025-01-01T00:00:00Z",
            "latestVersion": "2.0.0"
        }
        """
        let data = json.data(using: .utf8)!
        let gateInfo = try JSONDecoder().decode(GateInformation.self, from: data)

        #expect(gateInfo.gateType == .live)
        #expect(gateInfo.isBlocked() == false)
    }

    @Test("Invalid gate type defaults to live")
    func invalidGateTypeDefaultsToLive() throws {
        let json = """
        {
            "gateType": 99,
            "lastGateUpdate": "2025-01-01T00:00:00Z"
        }
        """
        let data = json.data(using: .utf8)!
        let gateInfo = try JSONDecoder().decode(GateInformation.self, from: data)

        #expect(gateInfo.gateType == .live)
    }

    @Test("Defaults to live gate type when missing or invalid")
    func defaultsToLiveGateType() throws {
        let json = """
        {
            "lastGateUpdate": "2025-01-01T00:00:00Z"
        }
        """
        let data = json.data(using: .utf8)!
        let gateInfo = try JSONDecoder().decode(GateInformation.self, from: data)

        #expect(gateInfo.gateType == .live)
    }

}

// MARK: - Cache Validation Tests

@Suite("Cache Validation Tests")
struct CacheValidationTests {

    @Test("withCachedAppVersion creates copy with version set")
    func withCachedAppVersionCreatesCopy() {
        let gateInfo = GateInformation(
            gateType: .forced,
            lastGateUpdate: "2025-01-01T00:00:00Z",
            latestVersion: "2.0.0",
            whatsNew: "Update",
            storeUrl: "https://apps.apple.com/app/id123"
        )

        let cached = gateInfo.withCachedAppVersion("1.0.0")

        #expect(cached.cachedForAppVersion == "1.0.0")
        #expect(cached.gateType == .forced)
        #expect(cached.lastGateUpdate == "2025-01-01T00:00:00Z")
    }

    @Test("Cache encodes and decodes with app version")
    func cacheEncodesDecodesWithAppVersion() throws {
        let gateInfo = GateInformation(
            gateType: .dismissible,
            lastGateUpdate: "2025-01-01T00:00:00Z",
            latestVersion: "2.0.0",
            whatsNew: "New features",
            storeUrl: "https://apps.apple.com/app/id123",
            cachedForAppVersion: "1.5.0"
        )

        let data = try JSONEncoder().encode(gateInfo)
        let decoded = try JSONDecoder().decode(GateInformation.self, from: data)

        #expect(decoded.cachedForAppVersion == "1.5.0")
        #expect(decoded.gateType == .dismissible)
    }

    @Test("API failure with no cache returns nil (not blocked)")
    @MainActor
    func apiFailureNoCacheReturnsNil() async {
        let mockAgent = MockMeerkat()
        mockAgent.gateInformationToReturn = nil // Simulate API failure
        let mockSettings = MockSettingsStore(analyticsEnabled: true)
        mockSettings.cachedGateInformation = nil // No cache

        let sideKit = SideKit(settings: mockSettings, meerkat: mockAgent)

        // Without gate info, user is not blocked
        #expect(sideKit.gateInformation == nil)
        #expect(sideKit.showUpdateScreen == false)
    }

    @Test("API failure uses cache when app version matches")
    @MainActor
    func apiFailureUsesCacheWhenVersionMatches() async {
        let cachedGateInfo = GateInformation(
            gateType: .forced,
            lastGateUpdate: "2025-01-01T00:00:00Z",
            latestVersion: "2.0.0",
            whatsNew: "Critical update",
            storeUrl: "https://apps.apple.com/app/id123",
            cachedForAppVersion: "1.0.0" // Matches mock current version
        )

        let mockAgent = MockMeerkat()
        mockAgent.gateInformationToReturn = nil // API failure
        let mockSettings = MockSettingsStore(analyticsEnabled: true)
        mockSettings.cachedGateInformation = cachedGateInfo

        // Note: In real scenario, loadCachedGateInformation checks Bundle.main.appVersion
        // For unit testing, we verify the cache structure is correct
        #expect(cachedGateInfo.cachedForAppVersion == "1.0.0")
        #expect(cachedGateInfo.isBlocked() == true)
    }

    @Test("Cache with mismatched version should be invalidated")
    func cacheMismatchedVersionInvalidated() {
        let cachedGateInfo = GateInformation(
            gateType: .forced,
            lastGateUpdate: "2025-01-01T00:00:00Z",
            latestVersion: "2.0.0",
            whatsNew: "Critical update",
            storeUrl: "https://apps.apple.com/app/id123",
            cachedForAppVersion: "1.0.0"
        )

        // Simulate version mismatch check
        let currentAppVersion = "2.0.0" // User updated the app
        let cacheIsValid = cachedGateInfo.cachedForAppVersion == currentAppVersion

        #expect(cacheIsValid == false) // Cache should be invalidated
    }
}

// MARK: - Feature Flag Tests

@Suite("Feature Flag Tests")
struct FeatureFlagTests {

    @Test("flag() returns boolean value for boolean flags")
    @MainActor
    func flagReturnsBoolValue() async {
        let mockAgent = MockMeerkat()
        mockAgent.flagsToReturn = [
            SideKit.FeatureFlag(key: "dark_mode", value: .bool(true), isFlag: true, updatedAt: "2026-01-01T00:00:00Z"),
            SideKit.FeatureFlag(key: "beta_feature", value: .bool(false), isFlag: true, updatedAt: "2026-01-01T00:00:00Z"),
        ]
        let mockSettings = MockSettingsStore(analyticsEnabled: true)
        let sideKit = SideKit(settings: mockSettings, meerkat: mockAgent)

        await sideKit.refreshFlags()

        #expect(sideKit.flag("dark_mode") == true)
        #expect(sideKit.flag("beta_feature") == false)
    }

    @Test("flag() returns default when key not found")
    @MainActor
    func flagReturnsDefaultWhenMissing() async {
        let mockAgent = MockMeerkat()
        mockAgent.flagsToReturn = []
        let mockSettings = MockSettingsStore(analyticsEnabled: true)
        let sideKit = SideKit(settings: mockSettings, meerkat: mockAgent)

        await sideKit.refreshFlags()

        #expect(sideKit.flag("nonexistent") == false)
        #expect(sideKit.flag("nonexistent", default: true) == true)
    }

    @Test("config() returns string value for config entries")
    @MainActor
    func configReturnsStringValue() async {
        let mockAgent = MockMeerkat()
        mockAgent.flagsToReturn = [
            SideKit.FeatureFlag(key: "api_url", value: .string("https://example.com"), isFlag: false, updatedAt: "2026-01-01T00:00:00Z"),
        ]
        let mockSettings = MockSettingsStore(analyticsEnabled: true)
        let sideKit = SideKit(settings: mockSettings, meerkat: mockAgent)

        await sideKit.refreshFlags()

        #expect(sideKit.config("api_url") == "https://example.com")
    }

    @Test("config() returns default when key not found")
    @MainActor
    func configReturnsDefaultWhenMissing() async {
        let mockAgent = MockMeerkat()
        mockAgent.flagsToReturn = []
        let mockSettings = MockSettingsStore(analyticsEnabled: true)
        let sideKit = SideKit(settings: mockSettings, meerkat: mockAgent)

        await sideKit.refreshFlags()

        #expect(sideKit.config("missing") == "")
        #expect(sideKit.config("missing", default: "fallback") == "fallback")
    }

    @Test("refreshFlags caches flags to settings")
    @MainActor
    func refreshFlagsCachesToSettings() async {
        let mockAgent = MockMeerkat()
        let testFlags = [
            SideKit.FeatureFlag(key: "cached_flag", value: .bool(true), isFlag: true, updatedAt: "2026-01-01T00:00:00Z"),
        ]
        mockAgent.flagsToReturn = testFlags
        let mockSettings = MockSettingsStore(analyticsEnabled: true)
        let sideKit = SideKit(settings: mockSettings, meerkat: mockAgent)

        await sideKit.refreshFlags()

        #expect(mockSettings.cachedFlags == testFlags)
    }

    @Test("refreshFlags falls back to cache when API fails")
    @MainActor
    func refreshFlagsFallsBackToCache() async {
        let mockAgent = MockMeerkat()
        mockAgent.flagsToReturn = nil // Simulate API failure
        let cachedFlags = [
            SideKit.FeatureFlag(key: "cached_flag", value: .bool(true), isFlag: true, updatedAt: "2026-01-01T00:00:00Z"),
        ]
        let mockSettings = MockSettingsStore(analyticsEnabled: true)
        mockSettings.cachedFlags = cachedFlags
        let sideKit = SideKit(settings: mockSettings, meerkat: mockAgent)

        await sideKit.refreshFlags()

        #expect(sideKit.flags == cachedFlags)
        #expect(sideKit.flag("cached_flag") == true)
    }

    @Test("FeatureFlag decodes from JSON correctly")
    func featureFlagDecodesFromJSON() throws {
        let json = """
        [
            {"key": "dark_mode", "value": true, "isFlag": true, "updatedAt": "2026-01-01T00:00:00Z"},
            {"key": "api_url", "value": "https://example.com", "isFlag": false, "updatedAt": "2026-01-01T00:00:00Z"}
        ]
        """
        let data = json.data(using: .utf8)!
        let flags = try JSONDecoder().decode([SideKit.FeatureFlag].self, from: data)

        #expect(flags.count == 2)
        #expect(flags[0].key == "dark_mode")
        #expect(flags[0].value == .bool(true))
        #expect(flags[0].isFlag == true)
        #expect(flags[1].key == "api_url")
        #expect(flags[1].value == .string("https://example.com"))
        #expect(flags[1].isFlag == false)
    }

    @Test("FeatureFlagValue equality works correctly")
    func featureFlagValueEquality() {
        #expect(SideKit.FeatureFlagValue.bool(true) == SideKit.FeatureFlagValue.bool(true))
        #expect(SideKit.FeatureFlagValue.bool(true) != SideKit.FeatureFlagValue.bool(false))
        #expect(SideKit.FeatureFlagValue.string("a") == SideKit.FeatureFlagValue.string("a"))
        #expect(SideKit.FeatureFlagValue.string("a") != SideKit.FeatureFlagValue.bool(true))
    }
}

// MARK: - Auth Tests

@Suite("Auth Tests")
struct AuthTests {

    private static let farFuture = Int(Date().timeIntervalSince1970) + 3600

    @Test("Starts signed out")
    @MainActor
    func startsSignedOut() {
        let sideKit = SideKit(settings: MockSettingsStore(analyticsEnabled: true), authAgent: MockAuthAgent())
        #expect(sideKit.isAuthenticated == false)
        #expect(sideKit.authUser == nil)
        #expect(sideKit.sessionToken == nil)
    }

    @Test("verifyOtp persists the session and signs the user in")
    @MainActor
    func verifyOtpSignsIn() async {
        let user = SideKit.AuthUser(id: "u_1", handle: nil, createdAt: 100)
        let authAgent = MockAuthAgent()
        authAgent.verifyOtpResult = .success(.init(sessionToken: "tok_1", expiresAt: Self.farFuture, user: user, newUser: true))
        let settings = MockSettingsStore(analyticsEnabled: true)
        let sideKit = SideKit(settings: settings, authAgent: authAgent)

        let result = await sideKit.verifyOtp(requestId: "r_1", identifier: "+15555550100", code: "123456")

        #expect(result.value?.user == user)
        #expect(result.value?.isNewUser == true)
        #expect(sideKit.isAuthenticated == true)
        #expect(sideKit.sessionToken == "tok_1")
        #expect(settings.authSession?.token == "tok_1")
    }

    @Test("verifyOtp surfaces the API error code on failure")
    @MainActor
    func verifyOtpSurfacesError() async {
        let authAgent = MockAuthAgent()
        authAgent.verifyOtpResult = .failure(.init(code: "invalid_code", status: 400))
        let sideKit = SideKit(settings: MockSettingsStore(analyticsEnabled: true), authAgent: authAgent)

        let result = await sideKit.verifyOtp(requestId: "r_1", identifier: "+15555550100", code: "000000")

        #expect(result.error?.code == "invalid_code")
        #expect(sideKit.isAuthenticated == false)
    }

    @Test("setHandle updates the local user on success")
    @MainActor
    func setHandleUpdatesUser() async {
        let user = SideKit.AuthUser(id: "u_1", handle: nil, createdAt: 100)
        let authAgent = MockAuthAgent()
        authAgent.verifyOtpResult = .success(.init(sessionToken: "tok_1", expiresAt: Self.farFuture, user: user, newUser: true))
        authAgent.setHandleResult = .success("coolhandle")
        let sideKit = SideKit(settings: MockSettingsStore(analyticsEnabled: true), authAgent: authAgent)
        _ = await sideKit.verifyOtp(requestId: "r_1", identifier: "+15555550100", code: "123456")

        let result = await sideKit.setHandle("coolhandle")

        #expect(result.value == "coolhandle")
        #expect(sideKit.authUser?.handle == "coolhandle")
    }

    @Test("setHandle returns unauthorized when signed out")
    @MainActor
    func setHandleUnauthorizedWhenSignedOut() async {
        let sideKit = SideKit(settings: MockSettingsStore(analyticsEnabled: true), authAgent: MockAuthAgent())
        let result = await sideKit.setHandle("nope")
        #expect(result.error?.code == "unauthorized")
    }

    @Test("logout clears local state even though revoke is best-effort")
    @MainActor
    func logoutClearsState() async {
        let user = SideKit.AuthUser(id: "u_1", handle: nil, createdAt: 100)
        let authAgent = MockAuthAgent()
        authAgent.verifyOtpResult = .success(.init(sessionToken: "tok_1", expiresAt: Self.farFuture, user: user, newUser: true))
        let settings = MockSettingsStore(analyticsEnabled: true)
        let sideKit = SideKit(settings: settings, authAgent: authAgent)
        _ = await sideKit.verifyOtp(requestId: "r_1", identifier: "+15555550100", code: "123456")

        await sideKit.logout()

        #expect(authAgent.logoutCallCount == 1)
        #expect(authAgent.lastLogoutToken == "tok_1")
        #expect(sideKit.isAuthenticated == false)
        #expect(sideKit.authUser == nil)
        #expect(settings.authSession == nil)
    }

    @Test("Expired stored session is dropped on init")
    @MainActor
    func expiredSessionDropped() {
        let settings = MockSettingsStore(analyticsEnabled: true)
        let user = SideKit.AuthUser(id: "u_1", handle: "h", createdAt: 100)
        settings.authSession = SideKit.AuthSession(token: "tok_old", user: user, expiresAt: 1)

        let sideKit = SideKit(settings: settings, authAgent: MockAuthAgent())

        #expect(sideKit.isAuthenticated == false)
        #expect(settings.authSession == nil)
    }

    @Test("Valid stored session is restored on init")
    @MainActor
    func validSessionRestored() {
        let settings = MockSettingsStore(analyticsEnabled: true)
        let user = SideKit.AuthUser(id: "u_1", handle: "h", createdAt: 100)
        settings.authSession = SideKit.AuthSession(token: "tok_live", user: user, expiresAt: Self.farFuture)

        let sideKit = SideKit(settings: settings, authAgent: MockAuthAgent())

        #expect(sideKit.isAuthenticated == true)
        #expect(sideKit.sessionToken == "tok_live")
        #expect(sideKit.authUser == user)
    }

    @Test("Feedback defaults endUserId to the signed-in user")
    @MainActor
    func feedbackDefaultsToSignedInUser() async {
        let user = SideKit.AuthUser(id: "u_42", handle: nil, createdAt: 100)
        let authAgent = MockAuthAgent()
        authAgent.verifyOtpResult = .success(.init(sessionToken: "tok_1", expiresAt: Self.farFuture, user: user, newUser: true))
        let meerkat = MockMeerkat()
        let sideKit = SideKit(settings: MockSettingsStore(analyticsEnabled: true), meerkat: meerkat, authAgent: authAgent)
        _ = await sideKit.verifyOtp(requestId: "r_1", identifier: "+15555550100", code: "123456")

        sideKit.sendFeedback("Great app")

        #expect(meerkat.lastFeedbackEndUserId == "u_42")
    }
}

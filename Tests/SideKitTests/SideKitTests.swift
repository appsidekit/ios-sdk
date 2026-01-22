//
//  SideKitTests.swift
//  SideKit
//

import Testing
import Foundation
@testable import SideKit

// MARK: - Mock Analytics Agent

@MainActor
final class MockAnalyticsAgent: AnalyticsAgentProtocol {
    var sendSignalCallCount = 0
    var lastSentSignals: [SideKit.Signal]?
    var gateInformationToReturn: GateInformation?

    func getGateInformation() async -> GateInformation? {
        return gateInformationToReturn
    }

    func sendSignal(signals: [SideKit.Signal]) {
        sendSignalCallCount += 1
        lastSentSignals = signals
    }
}

// MARK: - Mock Settings Store

final class MockSettingsStore: SettingsStoreProtocol {
    var isAnalyticsEnabled: Bool
    var isFirstLaunch: Bool = true
    var cachedGateInformation: GateInformation?

    init(analyticsEnabled: Bool) {
        self.isAnalyticsEnabled = analyticsEnabled
    }
}

// MARK: - Analytics Tests

@Suite("SideKit Analytics Tests")
struct SideKitAnalyticsTests {

    @Test("Signal is sent when analytics is enabled")
    @MainActor
    func signalSentWhenAnalyticsEnabled() async {
        let mockAgent = MockAnalyticsAgent()
        let mockSettings = MockSettingsStore(analyticsEnabled: true)
        let sideKit = SideKit(settings: mockSettings, analyticsAgent: mockAgent)

        sideKit.sendSignal(key: "test_event", value: "test_value")

        #expect(mockAgent.sendSignalCallCount == 1)
        #expect(mockAgent.lastSentSignals == [SideKit.Signal(name: "test_event", value: "test_value")])
    }

    @Test("Signal is NOT sent when analytics is disabled")
    @MainActor
    func signalNotSentWhenAnalyticsDisabled() async {
        let mockAgent = MockAnalyticsAgent()
        let mockSettings = MockSettingsStore(analyticsEnabled: false)
        let sideKit = SideKit(settings: mockSettings, analyticsAgent: mockAgent)

        sideKit.sendSignal(key: "test_event", value: "test_value")

        #expect(mockAgent.sendSignalCallCount == 0)
        #expect(mockAgent.lastSentSignals == nil)
    }

    @Test("Signal respects analytics toggle change")
    @MainActor
    func signalRespectsAnalyticsToggle() async {
        let mockAgent = MockAnalyticsAgent()
        let mockSettings = MockSettingsStore(analyticsEnabled: true)
        let sideKit = SideKit(settings: mockSettings, analyticsAgent: mockAgent)

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
        #expect(gateInfo.isDismissable == false)
        #expect(gateInfo.isForced == false)
    }

    @Test("Forced gate type is blocked and not dismissable")
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
        #expect(gateInfo.isDismissable == false)
        #expect(gateInfo.isForced == true)
    }

    @Test("Dismissable gate type is blocked and dismissable")
    func dismissableGateBlocked() {
        let gateInfo = GateInformation(
            gateType: .dismissable,
            lastGateUpdate: "2025-01-01T00:00:00Z",
            latestVersion: "2.0.0",
            whatsNew: "New features available",
            storeUrl: "https://apps.apple.com/app/id123"
        )

        #expect(gateInfo.isBlocked() == true)
        #expect(gateInfo.blockingGateType() == .dismissable)
        #expect(gateInfo.isDismissable == true)
        #expect(gateInfo.isForced == false)
    }

    @Test("Modal gate type is blocked and dismissable")
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
        #expect(gateInfo.isDismissable == true)
        #expect(gateInfo.isForced == false)
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
        #expect(VersionGateType.forced.rawValue == 0)
        #expect(VersionGateType.dismissable.rawValue == 1)
        #expect(VersionGateType.modal.rawValue == 2)
        #expect(VersionGateType.live.rawValue == 3)
    }

    @Test("Gate type can be created from raw values")
    func gateTypeFromRawValue() {
        #expect(VersionGateType(rawValue: 0) == .forced)
        #expect(VersionGateType(rawValue: 1) == .dismissable)
        #expect(VersionGateType(rawValue: 2) == .modal)
        #expect(VersionGateType(rawValue: 3) == .live)
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
            "gateType": 3,
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

    @Test("Handles invalid gate type value")
    func handlesInvalidGateType() throws {
        let json = """
        {
            "gateType": 999,
            "lastGateUpdate": "2025-01-01T00:00:00Z"
        }
        """
        let data = json.data(using: .utf8)!
        let gateInfo = try JSONDecoder().decode(GateInformation.self, from: data)

        #expect(gateInfo.gateType == .live) // Falls back to live
    }

    @Test("Handles gate type as wrong type (string instead of int)")
    func handlesGateTypeWrongType() throws {
        let json = """
        {
            "gateType": "forced",
            "lastGateUpdate": "2025-01-01T00:00:00Z"
        }
        """
        let data = json.data(using: .utf8)!
        let gateInfo = try JSONDecoder().decode(GateInformation.self, from: data)

        #expect(gateInfo.gateType == .live) // Falls back to live when type mismatch
    }

    @Test("Handles null gate type")
    func handlesNullGateType() throws {
        let json = """
        {
            "gateType": null,
            "lastGateUpdate": "2025-01-01T00:00:00Z"
        }
        """
        let data = json.data(using: .utf8)!
        let gateInfo = try JSONDecoder().decode(GateInformation.self, from: data)

        #expect(gateInfo.gateType == .live) // Falls back to live when null
    }

    @Test("Handles negative gate type value")
    func handlesNegativeGateType() throws {
        let json = """
        {
            "gateType": -1,
            "lastGateUpdate": "2025-01-01T00:00:00Z"
        }
        """
        let data = json.data(using: .utf8)!
        let gateInfo = try JSONDecoder().decode(GateInformation.self, from: data)

        #expect(gateInfo.gateType == .live) // Falls back to live for negative values
    }
}

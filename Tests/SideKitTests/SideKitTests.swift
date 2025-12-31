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

// MARK: - Tests

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
        sideKit.setAnalyticsEnabled(false)
        
        // Second signal should not be sent
        sideKit.sendSignal("event2")
        #expect(mockAgent.sendSignalCallCount == 1) // Still 1, not incremented
    }
}

@Suite("Semantic Version Tests")
struct SemanticVersionTests {
    
    @Test("Version parsing")
    func versionParsing() {
        let v1 = SemanticVersion(string: "1.2.3")
        #expect(v1?.components == [1, 2, 3])
        
        let v2 = SemanticVersion(string: "2.0")
        #expect(v2?.components == [2, 0])
        
        let v3 = SemanticVersion(string: "5")
        #expect(v3?.components == [5])
        
        let v4 = SemanticVersion(string: "1.2.3.4.5")
        #expect(v4?.components == [1, 2, 3, 4, 5])
    }
    
    @Test("Version comparison - less than")
    func versionLessThan() {
        let v1_0_0 = SemanticVersion(string: "1.0.0")!
        let v1_0_1 = SemanticVersion(string: "1.0.1")!
        let v1_1_0 = SemanticVersion(string: "1.1.0")!
        let v2_0_0 = SemanticVersion(string: "2.0.0")!
        
        #expect(v1_0_0 < v1_0_1)
        #expect(v1_0_0 < v1_1_0)
        #expect(v1_0_0 < v2_0_0)
        #expect(v1_0_1 < v1_1_0)
        #expect(v1_1_0 < v2_0_0)
    }
    
    @Test("Version comparison - equality")
    func versionEquality() {
        let v1 = SemanticVersion(string: "1.2.3")!
        let v2 = SemanticVersion(string: "1.2.3")!
        
        #expect(v1 == v2)
    }
    
    @Test("Version comparison - equality with different component counts")
    func versionEqualityDifferentCounts() {
        let v1 = SemanticVersion(string: "1.2.0")!
        let v2 = SemanticVersion(string: "1.2")!
        
        #expect(v1 == v2)
        
        let v3 = SemanticVersion(string: "2.0.0.0")!
        let v4 = SemanticVersion(string: "2")!
        
        #expect(v3 == v4)
    }
    
    @Test("Version comparison - 2.0.0 should NOT be less than 1.9.0")
    func versionComparisonFix() {
        let v2_0_0 = SemanticVersion(string: "2.0.0")!
        let v1_9_0 = SemanticVersion(string: "1.9.0")!
        
        #expect(v1_9_0 < v2_0_0)
        #expect(!(v2_0_0 < v1_9_0))
    }
    
    @Test("Version comparison - arbitrary length versions")
    func arbitraryLengthVersions() {
        let v1 = SemanticVersion(string: "1.2.3.4")!
        let v2 = SemanticVersion(string: "1.2.3.5")!
        let v3 = SemanticVersion(string: "1.2.4")!
        
        #expect(v1 < v2)
        #expect(v1 < v3)
        #expect(v2 < v3)
    }
}

@Suite("Version Compliance Tests")
struct VersionComplianceTests {
    
    @Test("Blocking when below minimum version")
    func blockWhenBelowMinVersion() {
        let currentVersion = SemanticVersion(string: "1.0.0")!
        let gateInfo = GateInformation(
            lastGateUpdate: "",
            minVersion: Gate(version: "2.0.0", type: .forced),
            blockedVersions: [],
            latestVersion: nil,
            whatsNew: nil,
            appStoreURL: nil
        )
        
        #expect(gateInfo.isBlocked(currentVersion: currentVersion) == true)
    }
    
    @Test("NOT blocking when at minimum version")
    func noBlockWhenAtMinVersion() {
        let currentVersion = SemanticVersion(string: "2.0.0")!
        let gateInfo = GateInformation(
            lastGateUpdate: "",
            minVersion: Gate(version: "2.0.0", type: .forced),
            blockedVersions: [],
            latestVersion: nil,
            whatsNew: nil,
            appStoreURL: nil
        )
        
        #expect(gateInfo.isBlocked(currentVersion: currentVersion) == false)
    }
    
    @Test("NOT blocking when above minimum version")
    func noBlockWhenAboveMinVersion() {
        let currentVersion = SemanticVersion(string: "3.0.0")!
        let gateInfo = GateInformation(
            lastGateUpdate: "",
            minVersion: Gate(version: "2.0.0", type: .forced),
            blockedVersions: [],
            latestVersion: nil,
            whatsNew: nil,
            appStoreURL: nil
        )
        
        #expect(gateInfo.isBlocked(currentVersion: currentVersion) == false)
    }
    
    @Test("Blocking when on blocked version")
    func blockWhenOnBlockedVersion() {
        let currentVersion = SemanticVersion(string: "2.1.0")!
        let gateInfo = GateInformation(
            lastGateUpdate: "",
            minVersion: Gate(version: "1.0.0", type: .forced),
            blockedVersions: [Gate(version: "2.1.0", type: .forced)],
            latestVersion: nil,
            whatsNew: nil,
            appStoreURL: nil
        )
        
        #expect(gateInfo.isBlocked(currentVersion: currentVersion) == true)
    }
    
    @Test("NOT blocking when not on blocked version")
    func noBlockWhenNotOnBlockedVersion() {
        let currentVersion = SemanticVersion(string: "2.2.0")!
        let gateInfo = GateInformation(
            lastGateUpdate: "",
            minVersion: Gate(version: "1.0.0", type: .forced),
            blockedVersions: [Gate(version: "2.1.0", type: .forced)],
            latestVersion: nil,
            whatsNew: nil,
            appStoreURL: nil
        )
        
        #expect(gateInfo.isBlocked(currentVersion: currentVersion) == false)
    }
    
    @Test("Blocking when both below min AND on blocked version")
    func blockWhenBothConditionsMet() {
        // This version is below min AND is the blocked version
        let currentVersion = SemanticVersion(string: "1.5.0")!
        let gateInfo = GateInformation(
            lastGateUpdate: "",
            minVersion: Gate(version: "2.0.0", type: .forced),
            blockedVersions: [Gate(version: "1.5.0", type: .forced)],
            latestVersion: nil,
            whatsNew: nil,
            appStoreURL: nil
        )
        
        #expect(gateInfo.isBlocked(currentVersion: currentVersion) == true)
    }
    
    @Test("NOT blocking when no requirements")
    func noBlockWhenNoRequirements() {
        let currentVersion = SemanticVersion(string: "1.0.0")!
        let gateInfo = GateInformation(
            lastGateUpdate: "",
            minVersion: nil,
            blockedVersions: [],
            latestVersion: nil,
            whatsNew: nil,
            appStoreURL: nil
        )
        
        #expect(gateInfo.isBlocked(currentVersion: currentVersion) == false)
    }
}
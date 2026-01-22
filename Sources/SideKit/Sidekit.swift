//
//  SideKit.swift
//  SideKit
//
//  Created by Ashish Selvaraj on 2025-12-04.
//

import Foundation
import SwiftUI

@MainActor
public final class SideKit: ObservableObject {
    @Published public var showUpdateScreen = false
    @Published public var gateInformation: GateInformation?
    @Published public var isAnalyticsEnabled: Bool = true {
        didSet { settings.isAnalyticsEnabled = isAnalyticsEnabled }
    }
    private var presentationMode: UpdatePresentationMode = .automatic
    
    public enum UpdatePresentationMode {
        /// Developer handles showing the update screen manually using `SideKit.shared.showUpdateScreen`
        case manual
        /// Automatically presents the update screen over your app (works for both SwiftUI and UIKit)
        case automatic
    }
    
    private let settings: SettingsStoreProtocol
    private var analyticsAgent: AnalyticsAgentProtocol?
    
    // Track notification observers to prevent duplicates and allow cleanup
    #if canImport(UIKit)
    private var appBecomeActiveObserver: NSObjectProtocol?
    #elseif os(macOS)
    private var appBecomeActiveObserver: NSObjectProtocol?
    #endif
    
    /// Controls whether verbose logging is enabled. Set via `configure(apiKey:presentationMode:verbose:)`.
    nonisolated(unsafe) internal static var isVerbose = false

    private enum DefaultSignals {
        static let firstLaunch = "_first_launch"
        static let appOpen = "_app_open"
        static let gateEnforced = "_gate_enforced"
    }

    public static let shared = SideKit()
    
    /// Internal initializer for testing.
    init(settings: SettingsStoreProtocol = SettingsStore(), analyticsAgent: AnalyticsAgentProtocol? = nil) {
        self.settings = settings
        self.analyticsAgent = analyticsAgent
        self.isAnalyticsEnabled = settings.isAnalyticsEnabled
    }
    
    /// Entry point for the SDK. Call this as early as possible in your app's lifecycle.
    /// - Parameters:
    ///   - apiKey: Your SideKit API key
    ///   - presentationMode: How the update gate should be presented (default: `.automatic`)
    ///   - verbose: Whether to enable verbose logging (default: `false`)
    public func configure(apiKey: String, presentationMode: UpdatePresentationMode = .automatic, verbose: Bool = false) async {
        self.presentationMode = presentationMode
        Self.isVerbose = verbose
        analyticsAgent = AnalyticsAgent(apiKey: apiKey)
        
        // Tracking default signals
        if settings.isFirstLaunch {
            sendSignal(DefaultSignals.firstLaunch)
            settings.isFirstLaunch = false
        }
        
        setupLifecycleObservers()
        handleAppOpen()
    }
    
    private func setupLifecycleObservers() {
        // Remove existing observer if configure() is called multiple times
        if let existingObserver = appBecomeActiveObserver {
            NotificationCenter.default.removeObserver(existingObserver)
            appBecomeActiveObserver = nil
        }
        
        #if canImport(UIKit)
        appBecomeActiveObserver = NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            self?.handleAppOpen()
        }
        #elseif os(macOS)
        appBecomeActiveObserver = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.handleAppOpen()
        }
        #endif
    }
    
    private func handleAppOpen() {
        sendSignal(DefaultSignals.appOpen)
        
        Task {
            await checkVersionCompliance()
        }
    }
    
    // MARK: - Version Compliance
    
    /// Fetches gate information from the server or falls back to locally saved settings if the network is unavailable.
    private func fetchGateInformation() async -> GateInformation? {
        // Try to fetch from API first
        if let gateInfo = await analyticsAgent?.getGateInformation() {
            self.gateInformation = gateInfo
            cacheGateInformation(gateInfo)
            return gateInfo
        }
        
        // Fallback to cached settings
        if let cachedGateInfo = loadCachedGateInformation() {
            self.gateInformation = cachedGateInfo
            return cachedGateInfo
        }
        
        return nil
    }
    
    /// Caches gate information to settings store with current app version
    private func cacheGateInformation(_ gateInfo: GateInformation) {
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let gateInfoWithVersion = gateInfo.withCachedAppVersion(appVersion)
        settings.cachedGateInformation = gateInfoWithVersion
        SKLog("Cached gate info for app version \(appVersion) - latestVersion: \(gateInfo.latestVersion ?? "nil"), whatsNew: \(gateInfo.whatsNew ?? "nil"), lastGateUpdate: \(gateInfo.lastGateUpdate)")
    }

    /// Loads gate information from cached settings if it matches current app version
    private func loadCachedGateInformation() -> GateInformation? {
        guard let cachedGateInfo = settings.cachedGateInformation else {
            return nil
        }

        // Validate cache is for current app version
        let currentAppVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        if let cachedVersion = cachedGateInfo.cachedForAppVersion, cachedVersion != currentAppVersion {
            SKLog("Cache invalidated - cached for version \(cachedVersion) but current version is \(currentAppVersion)")
            settings.cachedGateInformation = nil
            return nil
        }

        SKLog("Loaded cached gate info - latestVersion: \(cachedGateInfo.latestVersion ?? "nil"), whatsNew: \(cachedGateInfo.whatsNew ?? "nil"), lastGateUpdate: \(cachedGateInfo.lastGateUpdate)")
        return cachedGateInfo
    }

    /// Checks if the current version is compliant with the gate information.
    /// The server handles version comparison and returns the appropriate gate type directly.
    private func checkVersionCompliance() async {
        let previousGateUpdate = settings.cachedGateInformation?.lastGateUpdate

        guard let gateInfo = await fetchGateInformation() else {
            return
        }

        // Check if current version is blocked (server determined)
        let blockingGateType = gateInfo.blockingGateType()
        let isBlocked = blockingGateType != nil

        let isNewGate = previousGateUpdate != gateInfo.lastGateUpdate

        if isBlocked {
            // If it's not a new gate and the blocking gate is dismissable, we've already shown it - skip
            if !isNewGate && blockingGateType != .forced {
                SKLog("Gate already shown before (lastGateUpdate: \(gateInfo.lastGateUpdate)). Skipping dismissable gate.")
                return
            }
        } else {
            // Not blocked, nothing to show
            return
        }

        // For forced gates, always show regardless of whether we've seen it before
        // For new gates (different lastGateUpdate), always show
        SKLog("Gate type: \(gateInfo.gateType)")
        if isNewGate {
            SKLog("New gate detected (lastGateUpdate changed from \(previousGateUpdate ?? "nil") to \(gateInfo.lastGateUpdate))")
        }

        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        sendSignal(key: DefaultSignals.gateEnforced, value: appVersion)

        showUpdateScreen = true

        // Use the specific gate type that's blocking
        let isDismissable = blockingGateType != .forced
        processAutomaticPresentation(isDismissable: isDismissable)
    }
    
    private func processAutomaticPresentation(isDismissable: Bool) {
        guard presentationMode == .automatic else { return }
        #if canImport(UIKit)
        presentAutomaticUpdateGate(isDismissable: isDismissable)
        #endif
    }
    
    #if canImport(UIKit)
    private var updateWindow: UIWindow?
    
    private func presentAutomaticUpdateGate(isDismissable: Bool) {
        guard updateWindow == nil else { return }
        
        let gateView = DefaultVersionGate(
            dismissable: isDismissable,
            onSkip: { [weak self] in
                self?.dismissAutomaticUpdateGate()
            }
        )
        
        let hostingController = UIHostingController(rootView: gateView)
        hostingController.view.backgroundColor = .clear
        
        // Find the active window scene to attach our new window
        // Handle case where connectedScenes is empty or no scene is foreground active
        // Try to find any foreground scene if no foregroundActive scene exists (fallback)
        let scenes = UIApplication.shared.connectedScenes
        guard !scenes.isEmpty else {
            SKLog("Warning: No connected scenes available for automatic presentation")
            return
        }
        
        // First try to find a foreground active scene
        let windowScene = scenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
            // Fallback to any foreground scene if no foregroundActive scene exists
            ?? scenes.first(where: { $0.activationState == .foregroundInactive }) as? UIWindowScene
            // Last resort: use any available scene
            ?? scenes.first as? UIWindowScene
        
        guard let windowScene = windowScene else {
            SKLog("Warning: Could not find a valid window scene for automatic presentation")
            return
        }
        
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = hostingController
        window.windowLevel = .alert + 1 // Ensure it's above everything else
        window.backgroundColor = .clear
        window.makeKeyAndVisible()
        
        self.updateWindow = window
    }
    
    private func dismissAutomaticUpdateGate() {
        updateWindow?.isHidden = true
        updateWindow = nil
        showUpdateScreen = false
    }
    #endif
    
    // MARK: - Analytics
    
    /// Send an analytics signal with a single key.
    public func sendSignal(_ key: String) {
        sendSignal(Signal(name: key, value: ""))
    }
    
    /// Send an analytics signal with a key-value pair.
    public func sendSignal(key: String, value: String) {
        sendSignal(Signal(name: key, value: value))
    }
    
    /// Send a single Signal object
    public func sendSignal(_ signal: Signal) {
        sendSignal([signal])
    }
    
    /// Send multiple Signal objects
    public func sendSignal(_ signals: [Signal]) {
        guard isAnalyticsEnabled else { return }
        
        guard let agent = analyticsAgent else {
            SKLog("Warning: sendSignal called before configure(). Call configure(apiKey:) first.")
            return
        }
        agent.sendSignal(signals: signals)
    }
        
}

// MARK: - Logging

internal func SKLog(_ message: String) {
    guard SideKit.isVerbose else { return }
    print("[SideKit] \(message)")
}

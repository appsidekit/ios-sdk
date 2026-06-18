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
    
    /// Returns `true` when the server reports a newer version than the current bundle version.
    public var isUpdateAvailable: Bool {
        guard let latest = gateInformation?.latestVersion,
              let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else {
            return false
        }
        return latest.compare(current, options: .numeric) == .orderedDescending
    }

    private let settings: SettingsStoreProtocol
    private var meerkat: MeerkatProtocol?
    private var authAgent: AuthAgentProtocol?
    
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
    init(settings: SettingsStoreProtocol = SettingsStore(), meerkat: MeerkatProtocol? = nil, authAgent: AuthAgentProtocol? = nil) {
        self.settings = settings
        self.meerkat = meerkat
        self.authAgent = authAgent
        self.isAnalyticsEnabled = settings.isAnalyticsEnabled
        restoreAuthSession()
    }
    
    /// Entry point for the SDK. Call this as early as possible in your app's lifecycle.
    /// - Parameters:
    ///   - apiKey: Your SideKit API key
    ///   - presentationMode: How the update gate should be presented (default: `.automatic`)
    ///   - verbose: Whether to enable verbose logging (default: `false`)
    public func configure(apiKey: String, presentationMode: UpdatePresentationMode = .automatic, verbose: Bool = false) async {
        self.presentationMode = presentationMode
        Self.isVerbose = verbose
        meerkat = Meerkat(apiKey: apiKey)
        authAgent = AuthAgent(apiKey: apiKey)

        // Restore a persisted end-user session, dropping it if it has expired.
        restoreAuthSession()

        // Tracking default signals
        if settings.isFirstLaunch {
            sendSignal(DefaultSignals.firstLaunch)
            settings.isFirstLaunch = false
        }
        
        setupLifecycleObservers()
        handleAppOpen()
        await refreshFlags()
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
        if let gateInfo = await meerkat?.getGateInformation() {
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
        SKLog("Cached gate info for app version \(appVersion) - gateType: \(gateInfo.gateType), latestVersion: \(gateInfo.latestVersion ?? "nil"), whatsNew: \(gateInfo.whatsNew ?? "nil"), lastGateUpdate: \(gateInfo.lastGateUpdate)")
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
            // If it's not a new gate and the blocking gate is dismissible, we've already shown it - skip
            if !isNewGate && blockingGateType != .forced {
                SKLog("Gate already shown before (lastGateUpdate: \(gateInfo.lastGateUpdate)). Skipping dismissible gate.")
                return
            }
        } else {
            // Not blocked - dismiss any existing gate
            if showUpdateScreen {
                SKLog("Gate lifted - user is no longer blocked")
                showUpdateScreen = false
                #if canImport(UIKit)
                dismissAutomaticUpdateGate()
                #endif
            }
            return
        }

        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        sendSignal(key: DefaultSignals.gateEnforced, value: appVersion)

        showUpdateScreen = true

        // Use the specific gate type that's blocking
        let isDismissible = blockingGateType != .forced
        processAutomaticPresentation(isDismissible: isDismissible)
    }
    
    private func processAutomaticPresentation(isDismissible: Bool) {
        guard presentationMode == .automatic else { return }
        #if canImport(UIKit)
        presentAutomaticUpdateGate(isDismissible: isDismissible)
        #endif
    }
    
    #if canImport(UIKit)
    private var updateWindow: UIWindow?
    
    private func presentAutomaticUpdateGate(isDismissible: Bool) {
        guard updateWindow == nil else { return }
        
        let gateView = DefaultVersionGate(
            dismissible: isDismissible,
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
    
    // MARK: - Feature Flags

    /// All feature flags fetched from the server. Updated on `configure()` and `refreshFlags()`.
    @Published public private(set) var flags: [FeatureFlag] = []

    /// Returns the boolean value of a flag, or `defaultValue` if the flag doesn't exist or isn't a boolean flag.
    public func flag(_ key: String, default defaultValue: Bool = false) -> Bool {
        guard let flag = flags.first(where: { $0.key == key }), flag.isFlag else {
            return defaultValue
        }
        return flag.value.boolValue ?? defaultValue
    }

    /// Returns the string value of a config entry, or `defaultValue` if the key doesn't exist or isn't a config entry.
    public func config(_ key: String, default defaultValue: String = "") -> String {
        guard let flag = flags.first(where: { $0.key == key }), !flag.isFlag else {
            return defaultValue
        }
        return flag.value.stringValue ?? defaultValue
    }

    /// Fetches the latest flags from the server. Falls back to cached flags on failure.
    public func refreshFlags() async {
        guard let agent = meerkat else {
            SKLog("Warning: refreshFlags called before configure(). Call configure(apiKey:) first.")
            return
        }

        if let fetched = await agent.getFlags() {
            self.flags = fetched
            settings.cachedFlags = fetched
            SKLog("Fetched \(fetched.count) flags from server")
        } else if let cached = settings.cachedFlags {
            self.flags = cached
            SKLog("Using \(cached.count) cached flags (server unavailable)")
        }
    }

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

        guard let agent = meerkat else {
            SKLog("Warning: sendSignal called before configure(). Call configure(apiKey:) first.")
            return
        }
        agent.sendSignal(signals: signals)
    }

    // MARK: - Feedback

    /// Send user feedback. Device metadata is collected automatically. When signed in,
    /// feedback is attributed to the current user unless you pass an explicit `endUserId`.
    /// - Parameters:
    ///   - feedbackText: The feedback content (required).
    ///   - endUserId: An optional identifier for the end user. Defaults to the signed-in user.
    ///   - userAttributes: Optional key-value attributes about the user.
    public func sendFeedback(
        _ feedbackText: String,
        endUserId: String? = nil,
        userAttributes: [String: String]? = nil
    ) {
        guard let agent = meerkat else {
            SKLog("Warning: sendFeedback called before configure(). Call configure(apiKey:) first.")
            return
        }
        let resolvedUserId = endUserId ?? authUser?.id
        agent.sendFeedback(feedbackText: feedbackText, endUserId: resolvedUserId, userAttributes: userAttributes)
    }

    // MARK: - Auth

    /// The currently signed-in end user, or `nil` when signed out.
    @Published public private(set) var authUser: AuthUser?

    private var sessionExpiresAt: Int?

    /// `true` when an end user is signed in (and the session hasn't expired).
    public var isAuthenticated: Bool { sessionToken != nil }

    /// The opaque session token for the signed-in user, or `nil`. Send this to your own
    /// backend (e.g. as a Bearer header) and verify it via `/v1/auth/introspect`. Treat it
    /// as a credential.
    public private(set) var sessionToken: String?

    /// Start signing a user in: send a one-time passcode to an identifier on the given
    /// channel, then complete with `verifyOtp`. This is passwordless, so the same call
    /// signs up a new user and signs in an existing one. Defaults to `.phone` (E.164,
    /// e.g. "+15555550100"); pass `.email` for an email address. Returns the requestId to
    /// pass to `verifyOtp`, or an error (`rate_limited`, etc.).
    public func signIn(_ identifier: String, channel: AuthChannel = .phone, inviteCode: String? = nil) async -> AuthResult<AuthOtpResponse> {
        guard let authAgent else {
            return .failure(.init(code: "not_configured", status: 0))
        }
        return await authAgent.signIn(channel: channel, identifier: identifier, inviteCode: inviteCode)
    }

    /// Verify an OTP code. Pass the same `identifier`/`channel` used in `signIn`. On
    /// success the session and user are persisted and a ``SignInResult`` (the signed-in
    /// user plus `isNewUser`) is returned. Returns `invalid_code` on a bad code.
    public func verifyOtp(requestId: String, identifier: String, channel: AuthChannel = .phone, code: String) async -> AuthResult<SignInResult> {
        guard let authAgent else {
            return .failure(.init(code: "not_configured", status: 0))
        }
        let result = await authAgent.verifyOtp(requestId: requestId, channel: channel, identifier: identifier, code: code)
        switch result {
        case .success(let verified):
            applyAuthSession(token: verified.sessionToken, user: verified.user, expiresAt: verified.expiresAt)
            SKLog("Signed in as \(verified.user.id) (newUser: \(verified.newUser))")
            return .success(SignInResult(user: verified.user, isNewUser: verified.newUser))
        case .failure(let err):
            return .failure(err)
        }
    }

    /// Set the signed-in user's handle. Returns `handle_taken` (409) on conflict,
    /// `unauthorized` if signed out.
    public func setHandle(_ handle: String) async -> AuthResult<String> {
        guard let authAgent else {
            return .failure(.init(code: "not_configured", status: 0))
        }
        guard let token = sessionToken else {
            return .failure(.init(code: "unauthorized", status: 401))
        }
        let result = await authAgent.setHandle(token: token, handle: handle)
        if case .success(let newHandle) = result, let user = authUser {
            authUser = AuthUser(id: user.id, handle: newHandle, createdAt: user.createdAt)
            persistCurrentSession()
        }
        return result
    }

    /// Sign out. Revokes the session server-side (best-effort) and always clears local auth
    /// state — a network failure still signs the user out locally.
    public func logout() async {
        if let token = sessionToken, let authAgent {
            _ = await authAgent.logout(token: token) // best-effort; revoke is idempotent
        }
        authUser = nil
        sessionToken = nil
        sessionExpiresAt = nil
        settings.authSession = nil
        SKLog("Signed out")
    }

    /// Restore a persisted session, dropping it if it has expired.
    private func restoreAuthSession() {
        guard let session = settings.authSession else { return }
        if session.expiresAt <= Int(Date().timeIntervalSince1970) {
            SKLog("Stored session expired, clearing")
            settings.authSession = nil
            return
        }
        sessionToken = session.token
        authUser = session.user
        sessionExpiresAt = session.expiresAt
        SKLog("Restored session for \(session.user.id)")
    }

    /// Set the in-memory session and persist it.
    private func applyAuthSession(token: String, user: AuthUser, expiresAt: Int) {
        sessionToken = token
        authUser = user
        sessionExpiresAt = expiresAt
        settings.authSession = AuthSession(token: token, user: user, expiresAt: expiresAt)
    }

    /// Re-persist the current session (e.g. after the handle changes).
    private func persistCurrentSession() {
        guard let token = sessionToken, let user = authUser, let expiresAt = sessionExpiresAt else { return }
        settings.authSession = AuthSession(token: token, user: user, expiresAt: expiresAt)
    }

}

// MARK: - Logging

internal func SKLog(_ message: String) {
    guard SideKit.isVerbose else { return }
    print("[SideKit] \(message)")
}

//
//  GateInformation.swift
//  SideKit
//
//  Created by Ashish Selvaraj on 2025-12-04.
//

import Foundation

/// Version gate type enum matching backend
/// The server determines the appropriate gate type based on the app version
public enum VersionGateType: Int, Codable {
    case forced = 0
    case dismissable = 1
    case modal = 2
    case live = 3
}

/// Gate information from the version API
/// The server now handles version comparison and returns the appropriate gate type directly
public struct GateInformation: Codable {
    /// The gate type determined by the server based on the app version
    public let gateType: VersionGateType
    /// ISO 8601 timestamp of last gate update (used for cache invalidation)
    public let lastGateUpdate: String
    /// The latest available version in the store
    public let latestVersion: String?
    /// Description of what's new in the latest version
    public let whatsNew: String?
    /// App Store URL for this app
    public let storeUrl: String?
    /// The app version this gate info was fetched for (used for cache validation)
    public let cachedForAppVersion: String?

    public init(gateType: VersionGateType, lastGateUpdate: String, latestVersion: String?, whatsNew: String?, storeUrl: String?, cachedForAppVersion: String? = nil) {
        self.gateType = gateType
        self.lastGateUpdate = lastGateUpdate
        self.latestVersion = latestVersion
        self.whatsNew = whatsNew
        self.storeUrl = storeUrl
        self.cachedForAppVersion = cachedForAppVersion
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Gate type with fallback to live (not blocked)
        if let typeValue = try? container.decode(Int.self, forKey: .gateType),
           let decodedType = VersionGateType(rawValue: typeValue) {
            gateType = decodedType
        } else {
            gateType = .live
        }

        lastGateUpdate = (try? container.decode(String.self, forKey: .lastGateUpdate)) ?? ""
        latestVersion = try? container.decode(String.self, forKey: .latestVersion)
        whatsNew = try? container.decode(String.self, forKey: .whatsNew)
        storeUrl = try? container.decode(String.self, forKey: .storeUrl)
        cachedForAppVersion = try? container.decode(String.self, forKey: .cachedForAppVersion)
    }

    private enum CodingKeys: String, CodingKey {
        case gateType
        case lastGateUpdate
        case latestVersion
        case whatsNew
        case storeUrl
        case cachedForAppVersion
    }

    /// Returns a copy with the cachedForAppVersion set
    public func withCachedAppVersion(_ appVersion: String) -> GateInformation {
        return GateInformation(
            gateType: gateType,
            lastGateUpdate: lastGateUpdate,
            latestVersion: latestVersion,
            whatsNew: whatsNew,
            storeUrl: storeUrl,
            cachedForAppVersion: appVersion
        )
    }

    /// Returns the blocking gate type, or nil if not blocked (i.e., gate type is live)
    public func blockingGateType() -> VersionGateType? {
        return gateType == .live ? nil : gateType
    }

    /// Checks if the current version is blocked based on gate information
    public func isBlocked() -> Bool {
        return gateType != .live
    }

    /// Computed property to determine if the gate is dismissable
    public var isDismissable: Bool {
        return gateType == .dismissable || gateType == .modal
    }

    /// Computed property to determine if the gate is forced (cannot be dismissed)
    public var isForced: Bool {
        return gateType == .forced
    }
}

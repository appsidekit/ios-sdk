//
//  GateInformation.swift
//  SideKit
//
//  Created by Ashish Selvaraj on 2025-12-04.
//

import Foundation

/// Version gate type enum matching backend
public enum VersionGateType: Int, Codable {
    case forced = 0
    case dismissable = 1
    case modal = 2
}

// Internal types for parsing API response
private enum StoreType: Int, Codable {
    case appStore = 0
}

/// Gate structure matching backend
public struct Gate: Codable {
    public let version: String
    public let type: VersionGateType
    
    public init(version: String, type: VersionGateType) {
        self.version = version
        self.type = type
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Version is required, but provide empty string as fallback
        version = (try? container.decode(String.self, forKey: .version)) ?? ""
        
        // Type defaults to dismissable if missing or invalid
        if let typeValue = try? container.decode(Int.self, forKey: .type),
           let decodedType = VersionGateType(rawValue: typeValue) {
            type = decodedType
        } else {
            type = .dismissable
        }
    }
    
    private enum CodingKeys: String, CodingKey {
        case version
        case type
    }
}

/// Gate information from the version API
public struct GateInformation: Codable {
    public let lastGateUpdate: String
    public let minVersion: Gate?
    public let blockedVersions: [Gate]
    public let latestVersion: String?
    public let whatsNew: String?
    public let appStoreURL: String?
    
    public init(lastGateUpdate: String, minVersion: Gate?, blockedVersions: [Gate], latestVersion: String?, whatsNew: String?, appStoreURL: String?) {
        self.lastGateUpdate = lastGateUpdate
        self.minVersion = minVersion
        self.blockedVersions = blockedVersions
        self.latestVersion = latestVersion
        self.whatsNew = whatsNew
        self.appStoreURL = appStoreURL
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Use try? for all fields to handle missing or invalid fields gracefully
        // Provide sensible defaults for required fields
        lastGateUpdate = (try? container.decode(String.self, forKey: .lastGateUpdate)) ?? ""
        minVersion = try? container.decode(Gate.self, forKey: .minVersion)
        
        // Decode blockedVersions array - if decoding fails, use empty array
        // This prevents crashes from invalid or missing data
        blockedVersions = (try? container.decode([Gate].self, forKey: .blockedVersions)) ?? []
        
        latestVersion = try? container.decode(String.self, forKey: .latestVersion)
        whatsNew = try? container.decode(String.self, forKey: .whatsNew)
        
        // Extract App Store URL from storeUrls array
        if let storeUrls = try? container.decode([StoreUrl].self, forKey: .storeUrls) {
            appStoreURL = storeUrls.first(where: { $0.type == .appStore || $0.type == nil })?.url
        } else {
            appStoreURL = nil
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(lastGateUpdate, forKey: .lastGateUpdate)
        try container.encode(minVersion, forKey: .minVersion)
        try container.encode(blockedVersions, forKey: .blockedVersions)
        try container.encode(latestVersion, forKey: .latestVersion)
        try container.encode(whatsNew, forKey: .whatsNew)
        try container.encode(appStoreURL, forKey: .appStoreURL)
    }
    
    private enum CodingKeys: String, CodingKey {
        case lastGateUpdate
        case minVersion
        case blockedVersions
        case latestVersion
        case whatsNew
        case storeUrls
        case appStoreURL
    }
    
    /// Computed property to determine if the gate is dismissable
    public var isDismissable: Bool {
        minVersion?.type != .forced && blockedVersions.allSatisfy { $0.type != .forced }
    }
    
    /// Checks if the current version is blocked based on gate information
    /// Returns the gate type of the blocking gate, or nil if not blocked
    public func blockingGateType(currentVersion: SemanticVersion) -> VersionGateType? {
        // Check minimum version requirement first
        if let minVersionGate = minVersion,
           let minVersionString = SemanticVersion(string: minVersionGate.version),
           currentVersion < minVersionString {
            return minVersionGate.type
        }
        
        // Check if current version is explicitly blocked
        for blockedGate in blockedVersions {
            if let blockedVersion = SemanticVersion(string: blockedGate.version),
               currentVersion == blockedVersion {
                return blockedGate.type
            }
        }
        
        return nil
    }
    
    /// Checks if the current version is blocked based on gate information
    public func isBlocked(currentVersion: SemanticVersion) -> Bool {
        return blockingGateType(currentVersion: currentVersion) != nil
    }
}

// Internal struct for parsing API response
private struct StoreUrl: Codable {
    let type: StoreType?
    let url: String?
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Type defaults to appStore if missing or invalid
        if let typeValue = try? container.decode(Int.self, forKey: .type),
           let decodedType = StoreType(rawValue: typeValue) {
            type = decodedType
        } else {
            type = .appStore
        }
        
        url = try? container.decode(String.self, forKey: .url)
    }
    
    private enum CodingKeys: String, CodingKey {
        case type
        case url
    }
}

//
//  SemanticVersion.swift
//  SideKit
//
//  Created by Ashish Selvaraj on 2025-12-04.
//

import Foundation

/// A version representation that supports comparison with arbitrary number of components.
public struct SemanticVersion: Comparable, CustomStringConvertible {
    public let components: [Int]
    
    public var description: String {
        components.map(String.init).joined(separator: ".")
    }
    
    public init(components: [Int]) {
        self.components = components
    }
    
    /// Parse a version string like "1.2.3" or "1.2" or "1" or "1.2.3.4.5"
    public init?(string: String) {
        let parts = string
            .split(separator: ".")
            .compactMap { Int($0) }
        
        guard !parts.isEmpty else { return nil }
        
        self.components = parts
    }
    
    /// Normalizes two versions to have the same number of components by padding with zeros
    private static func normalized(_ lhs: SemanticVersion, _ rhs: SemanticVersion) -> ([Int], [Int]) {
        var lhsParts = lhs.components
        var rhsParts = rhs.components
        
        let maxCount = max(lhsParts.count, rhsParts.count)
        
        while lhsParts.count < maxCount {
            lhsParts.append(0)
        }
        while rhsParts.count < maxCount {
            rhsParts.append(0)
        }
        
        return (lhsParts, rhsParts)
    }
    
    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        let (lhsParts, rhsParts) = normalized(lhs, rhs)
        
        for i in 0..<lhsParts.count {
            if lhsParts[i] < rhsParts[i] { return true }
            if lhsParts[i] > rhsParts[i] { return false }
        }
        return false // equal
    }
    
    public static func == (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        let (lhsParts, rhsParts) = normalized(lhs, rhs)
        return lhsParts == rhsParts
    }
}

extension Bundle {
    var appVersion: SemanticVersion? {
        guard let versionString = infoDictionary?["CFBundleShortVersionString"] as? String else {
            return nil
        }
        return SemanticVersion(string: versionString)
    }
}

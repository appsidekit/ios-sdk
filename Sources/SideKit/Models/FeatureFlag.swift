//
//  FeatureFlag.swift
//  SideKit
//
//  Created by Ashish Selvaraj on 2026-03-01.
//

import Foundation

extension SideKit {
    /// A feature flag or config entry fetched from the SideKit dashboard.
    public struct FeatureFlag: Codable, Equatable, CustomStringConvertible {
        /// The flag key (e.g. "dark_mode_enabled").
        public let key: String
        /// The flag value — `true`/`false` for boolean flags, or a string for config entries.
        public let value: FeatureFlagValue
        /// Whether this entry is a boolean flag (`true`) or a string config (`false`).
        public let isFlag: Bool
        /// When this flag was last updated on the server (ISO 8601).
        public let updatedAt: String

        public var description: String {
            "\(key): \(value)"
        }
    }

    /// A value that can be either a boolean or a string, matching the backend representation.
    public enum FeatureFlagValue: Codable, Equatable, CustomStringConvertible {
        case bool(Bool)
        case string(String)

        public var boolValue: Bool? {
            if case .bool(let v) = self { return v }
            return nil
        }

        public var stringValue: String? {
            if case .string(let v) = self { return v }
            return nil
        }

        public var description: String {
            switch self {
            case .bool(let v): return v ? "true" : "false"
            case .string(let v): return v
            }
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let boolVal = try? container.decode(Bool.self) {
                self = .bool(boolVal)
            } else if let stringVal = try? container.decode(String.self) {
                self = .string(stringVal)
            } else {
                throw DecodingError.typeMismatch(
                    FeatureFlagValue.self,
                    DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected Bool or String")
                )
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .bool(let v): try container.encode(v)
            case .string(let v): try container.encode(v)
            }
        }
    }
}

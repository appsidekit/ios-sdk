//
//  Signal.swift
//  SideKit
//
//  Created by Ashish Selvaraj on 2025-12-24.
//

import Foundation

extension SideKit {
    public struct Signal: Codable, Equatable, CustomStringConvertible {
        public let name: String
        public let value: String
        
        public var description: String {
            if value.isEmpty {
                return name
            } else {
                return "\(name): \(value)"
            }
        }
        
        public init(name: String, value: String) {
            self.name = name
            self.value = value
        }
    }
}

struct SignalPayload: Codable {
    let osVersion: String
    let appVersion: String
    let country: String
    let language: String
    let platform: String
    let deviceModel: String
    let signals: [SideKit.Signal]

    init(
        osVersion: String,
        appVersion: String,
        country: String,
        language: String,
        platform: String,
        deviceModel: String,
        signals: [SideKit.Signal]
    ) {
        self.osVersion = osVersion
        self.appVersion = appVersion
        self.country = country
        self.language = language
        self.platform = platform
        self.deviceModel = deviceModel
        self.signals = signals
    }
}

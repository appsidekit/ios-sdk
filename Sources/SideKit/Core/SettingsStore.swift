//
//  SettingsStore.swift
//  SideKit
//
//  Created by Ashish Selvaraj on 2025-12-04.
//

import Foundation

protocol SettingsStoreProtocol: AnyObject {
    var isAnalyticsEnabled: Bool { get set }
    var isFirstLaunch: Bool { get set }
    var cachedGateInformation: GateInformation? { get set }
}

final class SettingsStore: SettingsStoreProtocol {
    private enum Keys {
        static let analyticsEnabled = "sk_analytics_enabled"
        static let firstLaunch = "sk_first_launch"
        static let cachedGateInformation = "sk_cached_gate_information"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Keys.analyticsEnabled: true,
            Keys.firstLaunch: true,
        ])
    }

    var isAnalyticsEnabled: Bool {
        get { defaults.bool(forKey: Keys.analyticsEnabled) }
        set { defaults.set(newValue, forKey: Keys.analyticsEnabled) }
    }

    var isFirstLaunch: Bool {
        get { defaults.bool(forKey: Keys.firstLaunch) }
        set { defaults.set(newValue, forKey: Keys.firstLaunch) }
    }

    var cachedGateInformation: GateInformation? {
        get {
            guard let data = defaults.data(forKey: Keys.cachedGateInformation),
                  let gateInfo = try? JSONDecoder().decode(GateInformation.self, from: data) else {
                return nil
            }
            return gateInfo
        }
        set {
            if let gateInfo = newValue,
               let data = try? JSONEncoder().encode(gateInfo) {
                defaults.set(data, forKey: Keys.cachedGateInformation)
            } else {
                defaults.removeObject(forKey: Keys.cachedGateInformation)
            }
        }
    }
}

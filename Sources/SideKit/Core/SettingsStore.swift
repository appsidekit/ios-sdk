//
//  SettingsStore.swift
//  SideKit
//
//  Created by Ashish Selvaraj on 2025-12-04.
//

import Foundation
import Combine

protocol SettingsStoreProtocol: AnyObject {
    var isAnalyticsEnabled: Bool { get set }
    var isFirstLaunch: Bool { get set }
    var cachedGateInformation: GateInformation? { get set }
}

final class SettingsStore: ObservableObject, SettingsStoreProtocol {
    private enum Keys {
        static let analyticsEnabled = "analytics_enabled"
        static let firstLaunch = "first_launch"
        static let cachedGateInformation = "cached_gate_information"
    }

    private let cancellable: Cancellable
    private let defaults: UserDefaults
    let objectWillChange = PassthroughSubject<Void, Never>()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        
        defaults.register(defaults: [
            Keys.analyticsEnabled: true,
            Keys.firstLaunch: true,
        ])
        
        cancellable = NotificationCenter.default
                    .publisher(for: UserDefaults.didChangeNotification)
                    .map { _ in () }
                    .subscribe(objectWillChange)
        
    }
    
    
    var isAnalyticsEnabled: Bool {
        set { defaults.set(newValue, forKey: Keys.analyticsEnabled) }
        get { defaults.bool(forKey: Keys.analyticsEnabled) }
    }
    
    var isFirstLaunch: Bool {
        set { defaults.set(newValue, forKey: Keys.firstLaunch) }
        get { defaults.bool(forKey: Keys.firstLaunch) }
    }
    
    /// Stores the entire GateInformation as JSON-encoded data
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

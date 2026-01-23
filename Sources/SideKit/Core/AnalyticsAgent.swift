//
//  AnalyticsAgent.swift
//  SideKit
//
//  Created by Ashish Selvaraj on 2025-11-24.
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

@MainActor
protocol AnalyticsAgentProtocol {
    func getGateInformation() async -> GateInformation?
    func sendSignal(signals: [SideKit.Signal])
}

@MainActor
final class AnalyticsAgent: AnalyticsAgentProtocol {
    let api = "https://api.appsidekit.com/"
    let apiKey: String
    
    init(apiKey: String) {
        self.apiKey = apiKey
    }
    
    private func configureHeaders(for request: inout URLRequest) {
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(apiKey, forHTTPHeaderField: "API-Key")
    }

    private var platform: String {
        #if os(iOS)
        return "iOS"
        #elseif os(macOS)
        return "macOS"
        #elseif os(watchOS)
        return "watchOS"
        #elseif os(tvOS)
        return "tvOS"
        #else
        return "unknown"
        #endif
    }

    private var deviceModel: String {
        #if os(iOS)
        return UIDevice.current.model
        #else
        return ""
        #endif
    }
    
    func getGateInformation() async -> GateInformation? {
        // Get app version for query parameter
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        guard !appVersion.isEmpty else {
            SKLog("Failed to get app version for gate information request")
            return nil
        }

        // Build URL with query parameters (storeType=0 for iOS App Store)
        var components = URLComponents(string: api + "v1/version")
        components?.queryItems = [
            URLQueryItem(name: "storeType", value: "0"),
            URLQueryItem(name: "appVersion", value: appVersion)
        ]

        guard let url = components?.url else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        configureHeaders(for: &request)

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let decoder = JSONDecoder()
            // Ignore unknown keys to handle extra fields gracefully
            decoder.keyDecodingStrategy = .useDefaultKeys
            // Decode with error handling - never crash
            do {
                let gateInfo = try decoder.decode(GateInformation.self, from: data)
                return gateInfo
            } catch {
                SKLog("Failed to decode gate information: \(error)")
                return nil
            }
        } catch {
            SKLog("Failed to fetch gate information: \(error)")
            return nil
        }
    }
    
    func sendSignal(signals: [SideKit.Signal]) {
        guard !signals.isEmpty else { return }
        
        // send signal
        guard let url = URL(string: api + "v1") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        // metadata
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let locale = Locale.current

        var country = "unknown"
        var language = "unknown"
        if #available(iOS 16, *) {
            country = locale.region?.identifier ?? "unknown"
            language = locale.language.languageCode?.identifier ?? "unknown"
        } else {
            country = locale.regionCode ?? "unknown"
            language = locale.languageCode ?? "unknown"
        }

        let payload = SignalPayload(
            osVersion: osVersion,
            appVersion: appVersion,
            country: country,
            language: language,
            platform: platform,
            deviceModel: deviceModel,
            signals: signals
        )
        
        guard let jsonData = try? JSONEncoder().encode(payload) else {
            return
        }
        request.httpBody = jsonData
        configureHeaders(for: &request)

        Task {
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode == 201 {
                        SKLog("Signals \(signals) sent successfully")
                    } else {
                        SKLog("Signals \(signals) failed with status: \(httpResponse.statusCode)")
                    }
                }
            } catch {
                SKLog("Sending signals \(signals) failed with error: \(error.localizedDescription)")
            }
        }
    }
}

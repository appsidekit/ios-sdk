//
//  Feedback.swift
//  SideKit
//
//  Created by Ashish Selvaraj on 2026-02-22.
//

import Foundation

extension SideKit {
    struct FeedbackPayload: Encodable {
        let feedbackText: String
        let endUserId: String?
        let userAttributes: [String: String]?
        let platform: String
        let appVersion: String
        let osVersion: String
        let country: String
        let language: String
        let deviceModel: String
    }
}

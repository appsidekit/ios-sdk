//
//  Auth.swift
//  SideKit
//
//  Created by Ashish Selvaraj on 2026-06-18.
//

import Foundation

extension SideKit {

    /// The channel an OTP identifier is delivered over. `phone` (SMS) is the only
    /// signup/login channel today; `email` is reserved for apps that make email their
    /// primary channel, and for adding a secondary channel to an existing account.
    public enum AuthChannel: String, Codable, Sendable {
        case phone
        case email
    }

    /// An authenticated end user of your app.
    public struct AuthUser: Codable, Equatable {
        /// Stable per-app user id (`u_…`); the id your backend keys end-user data on.
        public let id: String
        /// The user's chosen handle, or `nil` if they haven't set one yet.
        public let handle: String?
        /// Account creation time, Unix seconds.
        public let createdAt: Int

        public init(id: String, handle: String?, createdAt: Int) {
            self.id = id
            self.handle = handle
            self.createdAt = createdAt
        }
    }

    /// The error surfaced by a failed auth call. `code` is the short string the API
    /// returns (e.g. `"invalid_code"`, `"rate_limited"`, `"handle_taken"`,
    /// `"network_error"`), alongside the HTTP `status` and, for rate limits,
    /// `retryAfter` in seconds.
    public struct AuthError: Error, Equatable {
        public let code: String
        public let status: Int
        public let retryAfter: Int?

        public init(code: String, status: Int, retryAfter: Int? = nil) {
            self.code = code
            self.status = status
            self.retryAfter = retryAfter
        }
    }

    /// Result of an auth call. On `.success` the associated value holds the payload;
    /// on `.failure` it carries the ``AuthError`` the API surfaced.
    public enum AuthResult<Value> {
        case success(Value)
        case failure(AuthError)

        /// The payload on success, or `nil` on failure.
        public var value: Value? {
            if case .success(let v) = self { return v }
            return nil
        }

        /// The error on failure, or `nil` on success.
        public var error: AuthError? {
            if case .failure(let e) = self { return e }
            return nil
        }

        /// `true` when the call succeeded.
        public var isSuccess: Bool {
            if case .success = self { return true }
            return false
        }

        /// Transform the success payload, preserving any failure.
        func map<T>(_ transform: (Value) -> T) -> AuthResult<T> {
            switch self {
            case .success(let v): return .success(transform(v))
            case .failure(let e): return .failure(e)
            }
        }
    }

    /// Response from requesting an OTP.
    public struct AuthOtpResponse: Decodable, Equatable {
        /// Pass back to `verifyOtp` to complete the flow.
        public let requestId: String
        /// When the code expires, Unix seconds.
        public let expiresAt: Int
    }

    /// Response from verifying an OTP. Internal — `verifyOtp` returns a ``SignInResult``.
    struct AuthVerifyResponse: Decodable {
        let sessionToken: String
        let expiresAt: Int
        let user: SideKit.AuthUser
        /// `true` if this verify created the account (first sign-in), `false` for a returning user.
        let newUser: Bool
    }

    /// The outcome of a successful `verifyOtp`: the signed-in user plus whether the account
    /// was just created. Branch on `isNewUser` to route new users into onboarding (e.g.
    /// `setHandle`) and returning users straight into the app.
    public struct SignInResult: Equatable {
        public let user: AuthUser
        public let isNewUser: Bool

        public init(user: AuthUser, isNewUser: Bool) {
            self.user = user
            self.isNewUser = isNewUser
        }
    }

    /// A persisted end-user session: the token, the user it belongs to, and when it expires.
    struct AuthSession: Codable, Equatable {
        let token: String
        let user: SideKit.AuthUser
        let expiresAt: Int
    }

    /// Placeholder payload for endpoints that return an empty body (e.g. logout).
    public struct EmptyAuthResponse: Decodable, Equatable {
        public init() {}
    }
}

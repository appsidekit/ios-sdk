//
//  AuthAgent.swift
//  SideKit
//
//  Created by Ashish Selvaraj on 2026-06-18.
//
//  HTTP client for SideKit end-user auth (/v1/auth/*): the phone -> OTP -> session
//  flow plus handle/logout. Every call returns an AuthResult so callers can
//  branch on the error code the API surfaces (e.g. 'invalid_code', 'handle_taken').
//

import Foundation

@MainActor
protocol AuthAgentProtocol {
    func signIn(channel: SideKit.AuthChannel, identifier: String, inviteCode: String?) async -> SideKit.AuthResult<SideKit.AuthOtpResponse>
    func verifyOtp(requestId: String, channel: SideKit.AuthChannel, identifier: String, code: String) async -> SideKit.AuthResult<SideKit.AuthVerifyResponse>
    func setHandle(token: String, handle: String) async -> SideKit.AuthResult<String>
    func logout(token: String) async -> SideKit.AuthResult<SideKit.EmptyAuthResponse>
}

@MainActor
final class AuthAgent: AuthAgentProtocol {
    private let authBase = "https://api.appsidekit.com/v1/auth"
    private let apiKey: String

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    // MARK: - Endpoints

    /// POST /v1/auth/otp/send — send an OTP to a phone number or email address.
    func signIn(channel: SideKit.AuthChannel, identifier: String, inviteCode: String?) async -> SideKit.AuthResult<SideKit.AuthOtpResponse> {
        let body = OtpSendBody(identifier: .init(channel: channel, value: identifier), inviteCode: inviteCode)
        return await call(method: "POST", path: "/otp/send", body: try? JSONEncoder().encode(body))
    }

    /// POST /v1/auth/otp/verify — verify the code and mint a session.
    func verifyOtp(requestId: String, channel: SideKit.AuthChannel, identifier: String, code: String) async -> SideKit.AuthResult<SideKit.AuthVerifyResponse> {
        let body = OtpVerifyBody(requestId: requestId, identifier: .init(channel: channel, value: identifier), code: code)
        return await call(method: "POST", path: "/otp/verify", body: try? JSONEncoder().encode(body))
    }

    /// PUT /v1/auth/handle — set the signed-in user's handle (Bearer).
    func setHandle(token: String, handle: String) async -> SideKit.AuthResult<String> {
        let body = try? JSONEncoder().encode(HandleBody(handle: handle))
        let result: SideKit.AuthResult<HandleResponse> = await call(method: "PUT", path: "/handle", body: body, token: token)
        return result.map { $0.handle }
    }

    /// POST /v1/auth/logout — revoke the session (Bearer). Idempotent.
    func logout(token: String) async -> SideKit.AuthResult<SideKit.EmptyAuthResponse> {
        return await call(method: "POST", path: "/logout", body: nil, token: token)
    }

    // MARK: - Request bodies

    /// A signup/login identifier, encoded as the server's discriminated union: the value
    /// rides under a channel-specific key (`{channel:"phone", phone}` / `{channel:"email",
    /// email}`), which is how `/v1/auth/*` parses it.
    private struct Identifier: Encodable {
        let channel: SideKit.AuthChannel
        let value: String

        private enum CodingKeys: String, CodingKey {
            case channel, phone, email
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(channel, forKey: .channel)
            switch channel {
            case .phone: try c.encode(value, forKey: .phone)
            case .email: try c.encode(value, forKey: .email)
            }
        }
    }
    private struct OtpSendBody: Encodable {
        let identifier: Identifier
        let inviteCode: String?
    }
    private struct OtpVerifyBody: Encodable {
        let requestId: String
        let identifier: Identifier
        let code: String
    }
    private struct HandleBody: Encodable { let handle: String }

    private struct HandleResponse: Decodable { let handle: String }

    // MARK: - Transport

    /// Issue a request and map the response into an ``SideKit/AuthResult``. On 2xx the JSON
    /// body is decoded as `T` (an empty body decodes as `{}`); otherwise the short text error
    /// code the API returns becomes the ``SideKit/AuthError`` code, with the HTTP status and
    /// any `Retry-After` (seconds) attached.
    private func call<T: Decodable>(
        method: String,
        path: String,
        body: Data?,
        token: String? = nil
    ) async -> SideKit.AuthResult<T> {
        guard let url = URL(string: authBase + path) else {
            return .failure(.init(code: "invalid_url", status: 0))
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(apiKey, forHTTPHeaderField: "API-Key")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = body

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failure(.init(code: "network_error", status: 0))
            }

            if (200..<300).contains(http.statusCode) {
                // Tolerate an empty success body (e.g. logout) by decoding it as `{}`.
                let payload = data.isEmpty ? Data("{}".utf8) : data
                if let decoded = try? JSONDecoder().decode(T.self, from: payload) {
                    SKLog("Auth \(method) \(path) ok (\(http.statusCode))")
                    return .success(decoded)
                }
                SKLog("Auth \(method) \(path) ok (\(http.statusCode)) but body failed to decode")
                return .failure(.init(code: "decode_error", status: http.statusCode))
            }

            // Error responses carry a short text code as the body (e.g. 'invalid_code').
            let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let errorCode = text.isEmpty ? "http_\(http.statusCode)" : text
            let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap { Int($0) }

            SKLog("Auth \(method) \(path) failed (\(http.statusCode)): \(errorCode)")
            return .failure(.init(code: errorCode, status: http.statusCode, retryAfter: retryAfter))
        } catch {
            SKLog("Auth \(method) \(path) request failed: \(error.localizedDescription)")
            return .failure(.init(code: "network_error", status: 0))
        }
    }
}

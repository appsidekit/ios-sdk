//
//  Keychain.swift
//  SideKit
//
//  A minimal, robust Keychain-backed store for a single secret — the end-user
//  session token. The token is a bearer credential, so it must not live in
//  UserDefaults (an unencrypted plist that rides along in device backups and is
//  trivially readable on a compromised device).
//
//  Items are generic passwords scoped to this app, accessible after first
//  unlock (so background networking can read them while the device is locked)
//  and `ThisDeviceOnly` — they are excluded from backups and are never restored
//  to a new device. A session token shouldn't outlive the device it was minted
//  on; if a user migrates devices they simply re-authenticate.
//

import Foundation
import Security

enum Keychain {
    // Accessible after the first unlock following boot, and never leaves this
    // device (excluded from iCloud/iTunes backups and device restore).
    private static var accessibility: CFString { kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly }

    private static func baseQuery(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    /// Read the stored blob, or nil if absent / unreadable.
    static func get(service: String, account: String) -> Data? {
        var query = baseQuery(service: service, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    /// Upsert the blob. Updates an existing item in place (no window where the
    /// secret is briefly absent), falling back to insert when none exists.
    /// Returns true on success.
    @discardableResult
    static func set(_ data: Data, service: String, account: String) -> Bool {
        let query = baseQuery(service: service, account: account)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: accessibility,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return true }

        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = accessibility
            return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
        }

        // Unexpected failure (e.g. a wedged/duplicate item). Last resort: clear
        // and re-add so we don't get stuck unable to persist a session.
        SecItemDelete(query as CFDictionary)
        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = accessibility
        return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
    }

    /// Remove the stored blob. Returns true if it's gone afterward (including
    /// when it was already absent).
    @discardableResult
    static func delete(service: String, account: String) -> Bool {
        let status = SecItemDelete(baseQuery(service: service, account: account) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}

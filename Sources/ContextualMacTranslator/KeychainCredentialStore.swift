import Foundation
import Security

/// Errors thrown by `KeychainCredentialStore`.
public enum KeychainError: Error, Equatable {
    case unexpectedStatus(OSStatus)
    case dataConversionFailed
}

/// Thin wrapper around `SecItem*` for storing user secrets (API tokens, glossary).
///
/// Items are stored as `kSecClassGenericPassword` keyed by `(service, account)` and
/// gated by `kSecAttrAccessibleAfterFirstUnlock` so background workflows survive
/// across sessions but the data is unreadable until the device is unlocked once.
public struct KeychainCredentialStore: Sendable {
    public let service: String

    public init(service: String) {
        self.service = service
    }

    public func read(account: String) throws -> String? {
        var query = baseQuery(account: account)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = kCFBooleanTrue

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let string = String(data: data, encoding: .utf8) else {
                throw KeychainError.dataConversionFailed
            }
            return string
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    public func write(_ value: String, account: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.dataConversionFailed
        }

        let query = baseQuery(account: account)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var insert = query
            insert.merge(attributes) { _, new in new }
            let addStatus = SecItemAdd(insert as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(addStatus)
            }
        default:
            throw KeychainError.unexpectedStatus(updateStatus)
        }
    }

    public func delete(account: String) throws {
        let query = baseQuery(account: account)
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

/// One-time migration from `UserDefaults` to `KeychainCredentialStore`.
///
/// Reads the legacy value, writes it into Keychain (only if Keychain is empty),
/// then removes the legacy `UserDefaults` key. Safe to call on every launch.
public struct CredentialMigration {
    private let store: KeychainCredentialStore
    private let defaults: UserDefaults

    public init(store: KeychainCredentialStore, defaults: UserDefaults = .standard) {
        self.store = store
        self.defaults = defaults
    }

    public func migrateIfNeeded(userDefaultsKey: String, account: String) throws {
        let legacyValue = defaults.string(forKey: userDefaultsKey)
        let alreadyMigrated = try store.read(account: account)

        if alreadyMigrated == nil, let legacy = legacyValue, !legacy.isEmpty {
            try store.write(legacy, account: account)
        }

        defaults.removeObject(forKey: userDefaultsKey)
    }
}

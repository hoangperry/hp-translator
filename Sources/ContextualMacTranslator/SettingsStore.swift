import Foundation
import OSLog

@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    /// Bundle-scoped service identifier used for Keychain entries.
    /// Matches `CFBundleIdentifier` in `scripts/package_app.sh`.
    static let keychainService = "app.lookerlab.translator"

    @Published var endpoint: String {
        didSet {
            guard endpoint != oldValue else { return }
            defaults.set(endpoint, forKey: Keys.endpoint)
        }
    }

    @Published var apiKey: String {
        didSet {
            guard apiKey != oldValue else { return }
            writeAPIKey(apiKey)
        }
    }

    @Published var glossary: String {
        didSet {
            guard glossary != oldValue else { return }
            writeGlossary(glossary)
        }
    }

    @Published var focusGuardEnabled: Bool {
        didSet {
            guard focusGuardEnabled != oldValue else { return }
            defaults.set(focusGuardEnabled, forKey: Keys.focusGuardEnabled)
        }
    }

    @Published var firstRunCompleted: Bool {
        didSet {
            guard firstRunCompleted != oldValue else { return }
            defaults.set(firstRunCompleted, forKey: Keys.firstRunCompleted)
        }
    }

    private let defaults: UserDefaults
    private let keychain: KeychainCredentialStore
    private static let logger = Logger(subsystem: SettingsStore.keychainService, category: "settings")

    private enum Keys {
        static let endpoint = "translator.endpoint"
        static let apiKey = "translator.apiKey"
        static let glossary = "translator.glossary"
        static let focusGuardEnabled = "translator.focusGuardEnabled"
        static let firstRunCompleted = "translator.firstRunCompleted"
    }

    private enum Accounts {
        static let apiKey = "default-bearer-token"
        static let glossary = "default-glossary"
    }

    /// Default endpoint points to the reference backend running locally so
    /// first-launch with `translator-server` running on the same machine
    /// works without manual config. Users override in Settings for remote
    /// backends.
    static let defaultEndpoint = "http://127.0.0.1:8765/translate"

    init(
        defaults: UserDefaults = .standard,
        keychain: KeychainCredentialStore = KeychainCredentialStore(service: SettingsStore.keychainService)
    ) {
        self.defaults = defaults
        self.keychain = keychain

        // Migrate legacy UserDefaults secrets to Keychain on first launch.
        let migration = CredentialMigration(store: keychain, defaults: defaults)
        Self.migrateSecret(migration, key: Keys.apiKey, account: Accounts.apiKey)
        Self.migrateSecret(migration, key: Keys.glossary, account: Accounts.glossary)

        endpoint = defaults.string(forKey: Keys.endpoint) ?? Self.defaultEndpoint
        apiKey = (try? keychain.read(account: Accounts.apiKey)) ?? ""
        glossary = (try? keychain.read(account: Accounts.glossary)) ?? ""
        focusGuardEnabled = defaults.object(forKey: Keys.focusGuardEnabled) as? Bool ?? true
        firstRunCompleted = defaults.bool(forKey: Keys.firstRunCompleted)
    }

    private static func migrateSecret(_ migration: CredentialMigration, key: String, account: String) {
        do {
            try migration.migrateIfNeeded(userDefaultsKey: key, account: account)
        } catch {
            logger.error("Credential migration failed for \(key, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }

    private func writeAPIKey(_ value: String) {
        if value.isEmpty {
            try? keychain.delete(account: Accounts.apiKey)
        } else {
            try? keychain.write(value, account: Accounts.apiKey)
        }
    }

    private func writeGlossary(_ value: String) {
        if value.isEmpty {
            try? keychain.delete(account: Accounts.glossary)
        } else {
            try? keychain.write(value, account: Accounts.glossary)
        }
    }
}

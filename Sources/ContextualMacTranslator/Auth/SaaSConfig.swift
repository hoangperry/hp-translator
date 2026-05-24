import Foundation
import Observation

/// SaaS / Supabase configuration extracted from `SettingsStore` in
/// v0.9.2 to address W1 from the v0.9.0 deliver-phase review (god-object).
/// Owns:
///   • `supabaseURL` / `supabaseAnonKey` — observable, persist to
///     `UserDefaults`.
///   • `authConfig()` — composes a `SupabaseAuthConfig` for the auth
///     service; returns `nil` when either URL or anon key is missing.
///   • `makeSessionStore()` — Keychain-backed Supabase session store
///     factory shared by the Settings sign-in flow + the per-translation
///     provider.
///   • `translateEndpoint` — derived `/functions/v1/translate` URL.
///   • `deviceIdentity()` — stable per-Mac identity (Keychain-persisted
///     UUID + Host.current + ProcessInfo).
///
/// Pure behaviour-preserving refactor; storage layout (UserDefaults
/// keys, Keychain account names) is byte-identical to v0.9.1 so a
/// fresh v0.9.2 launch loads every existing user's state without
/// migration. Three accessors on `SettingsStore` (`supabaseURL`,
/// `supabaseAnonKey`, `supabaseAuthConfig()`, `makeSupabaseSessionStore()`,
/// `supabaseTranslateEndpoint`, `deviceIdentity()`) now live on this
/// type; `SettingsStore.shared.saaSConfig` is the migration path.
@MainActor
@Observable
final class SaaSConfig {
    /// Supabase project URL — public value, e.g. `https://<ref>.supabase.co`.
    var supabaseURL: String {
        didSet {
            guard supabaseURL != oldValue else { return }
            defaults.set(supabaseURL, forKey: Keys.supabaseURL)
        }
    }

    /// Supabase anon key — public by design (RLS protects data
    /// server-side, NOT this key).
    var supabaseAnonKey: String {
        didSet {
            guard supabaseAnonKey != oldValue else { return }
            defaults.set(supabaseAnonKey, forKey: Keys.supabaseAnonKey)
        }
    }

    /// `UserDefaults` keys for the two persisted properties. Identical
    /// strings to v0.9.1 so existing user state survives the rename.
    enum Keys {
        static let supabaseURL = "translator.supabase.url"
        static let supabaseAnonKey = "translator.supabase.anonKey"
    }

    /// Keychain account name for the per-Mac device-ID. Same string
    /// v0.9.1 used.
    private enum Accounts {
        static let deviceID = "saas-device-id"
    }

    private let defaults: UserDefaults
    private let keychain: KeychainCredentialStore

    init(
        defaults: UserDefaults,
        keychain: KeychainCredentialStore,
        defaultSupabaseURL: String,
        defaultSupabaseAnonKey: String
    ) {
        self.defaults = defaults
        self.keychain = keychain
        self.supabaseURL = defaults.string(forKey: Keys.supabaseURL) ?? defaultSupabaseURL
        self.supabaseAnonKey = defaults.string(forKey: Keys.supabaseAnonKey) ?? defaultSupabaseAnonKey
    }

    // MARK: - Composed views

    /// Build a `SupabaseAuthConfig` from the configured project URL +
    /// anon key. Returns `nil` when either is missing or the URL is
    /// unparseable.
    func authConfig() -> SupabaseAuthConfig? {
        let url = supabaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = supabaseAnonKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty, !key.isEmpty, let parsed = URL(string: url) else {
            return nil
        }
        return SupabaseAuthConfig(baseURL: parsed, anonKey: key)
    }

    /// Keychain-backed Supabase session store. Shared source of truth —
    /// both the Settings sign-in flow and the per-translation provider
    /// read it.
    func makeSessionStore() -> KeychainSupabaseSessionStore {
        KeychainSupabaseSessionStore(keychain: keychain)
    }

    /// SaaS `/translate` Edge Function endpoint derived from the project
    /// URL. Returns empty string when the project URL is unset.
    var translateEndpoint: String {
        let base = supabaseURL
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return base.isEmpty ? "" : base + "/functions/v1/translate"
    }

    /// Stable device identity for SaaS device registration (M2.1-c).
    /// The device ID is generated once and persisted in the Keychain;
    /// later calls return the same id. Display name + OS version are
    /// fetched fresh each call (cheap, and the OS version changes
    /// when the user upgrades macOS).
    func deviceIdentity() -> DeviceIdentity {
        let stored = (try? keychain.read(account: Accounts.deviceID)) ?? nil
        let id: String
        if let stored, !stored.isEmpty {
            id = stored
        } else {
            id = UUID().uuidString
            try? keychain.write(id, account: Accounts.deviceID)
        }
        return DeviceIdentity(
            deviceID: id,
            deviceName: Host.current().localizedName ?? "Mac",
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString
        )
    }
}

import Foundation
import Testing

@testable import ContextualMacTranslator

@Suite("SettingsStore")
@MainActor
struct SettingsStoreTests {
    private func makeDefaults(_ name: String = UUID().uuidString) -> UserDefaults {
        let suiteName = "app.lookerlab.translator.settings-tests.\(name)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func makeKeychain() -> KeychainCredentialStore {
        KeychainCredentialStore(service: "app.lookerlab.translator.settings-tests.\(UUID().uuidString)")
    }

    @Test("focus guard is enabled by default")
    func focusGuardEnabledByDefault() {
        let store = SettingsStore(defaults: makeDefaults(), keychain: makeKeychain())

        #expect(store.focusGuardEnabled == true)
    }

    @Test("focus guard toggle persists in UserDefaults")
    func focusGuardTogglePersists() {
        let defaults = makeDefaults("focus-toggle")
        let keychain = makeKeychain()
        let store = SettingsStore(defaults: defaults, keychain: keychain)

        store.focusGuardEnabled = false

        let reloaded = SettingsStore(defaults: defaults, keychain: keychain)
        #expect(reloaded.focusGuardEnabled == false)
    }

    @Test("assigning the same endpoint does not rewrite UserDefaults")
    func endpointNoopDoesNotRewrite() {
        let defaults = makeDefaults("endpoint-noop")
        let store = SettingsStore(defaults: defaults, keychain: makeKeychain())

        defaults.removeObject(forKey: "translator.endpoint")
        store.endpoint = store.endpoint

        #expect(defaults.string(forKey: "translator.endpoint") == nil)
    }

    @Test("first launch is incomplete by default and persists when completed")
    func firstRunCompletedPersists() {
        let defaults = makeDefaults("first-run")
        let store = SettingsStore(defaults: defaults, keychain: makeKeychain())

        #expect(store.firstRunCompleted == false)
        store.firstRunCompleted = true

        let reloaded = SettingsStore(defaults: defaults, keychain: makeKeychain())
        #expect(reloaded.firstRunCompleted == true)
    }
}

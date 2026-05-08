import Foundation
import Testing

@testable import ContextualMacTranslator

@Suite("KeychainCredentialStore")
@MainActor
struct KeychainCredentialStoreTests {
    private static let testService = "app.lookerlab.translator.test.\(UUID().uuidString)"

    private func makeStore() -> KeychainCredentialStore {
        KeychainCredentialStore(service: Self.testService)
    }

    @Test("read returns nil when no value stored")
    func readNilWhenAbsent() throws {
        let store = makeStore()
        try store.delete(account: "missing")
        #expect(try store.read(account: "missing") == nil)
    }

    @Test("write then read returns the same value")
    func writeAndRead() throws {
        let store = makeStore()
        defer { try? store.delete(account: "default") }

        try store.write("super-secret-token", account: "default")
        #expect(try store.read(account: "default") == "super-secret-token")
    }

    @Test("write overwrites existing value")
    func writeOverwrites() throws {
        let store = makeStore()
        defer { try? store.delete(account: "default") }

        try store.write("first", account: "default")
        try store.write("second", account: "default")
        #expect(try store.read(account: "default") == "second")
    }

    @Test("delete removes the entry")
    func deleteRemovesEntry() throws {
        let store = makeStore()

        try store.write("temporary", account: "default")
        try store.delete(account: "default")
        #expect(try store.read(account: "default") == nil)
    }

    @Test("delete is idempotent on missing entry")
    func deleteMissingIsNoop() throws {
        let store = makeStore()
        try store.delete(account: "never-existed")
        try store.delete(account: "never-existed")
    }

    @Test("read handles unicode payloads")
    func unicodePayload() throws {
        let store = makeStore()
        defer { try? store.delete(account: "glossary") }

        let glossary = "API gateway = APIゲートウェイ\nrelease train = リリーストレイン\n# 注釈"
        try store.write(glossary, account: "glossary")
        #expect(try store.read(account: "glossary") == glossary)
    }
}

@Suite("CredentialMigration")
@MainActor
struct CredentialMigrationTests {
    private static let testService = "app.lookerlab.translator.migration.\(UUID().uuidString)"
    private static let userDefaultsSuiteName = "app.lookerlab.translator.migration-tests"

    private func makeStore() -> KeychainCredentialStore {
        KeychainCredentialStore(service: Self.testService)
    }

    private func makeDefaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: Self.userDefaultsSuiteName)!
        defaults.removePersistentDomain(forName: Self.userDefaultsSuiteName)
        return defaults
    }

    @Test("migration moves value from UserDefaults to Keychain and clears UD")
    func migratesAndClears() throws {
        let store = makeStore()
        let defaults = makeDefaults()
        defer { try? store.delete(account: "default") }

        defaults.set("legacy-token", forKey: "translator.apiKey")
        let migration = CredentialMigration(store: store, defaults: defaults)

        try migration.migrateIfNeeded(
            userDefaultsKey: "translator.apiKey",
            account: "default"
        )

        #expect(try store.read(account: "default") == "legacy-token")
        #expect(defaults.string(forKey: "translator.apiKey") == nil)
    }

    @Test("migration is idempotent — does not overwrite existing keychain value")
    func idempotent() throws {
        let store = makeStore()
        let defaults = makeDefaults()
        defer { try? store.delete(account: "default") }

        try store.write("already-migrated", account: "default")
        defaults.set("legacy-but-stale", forKey: "translator.apiKey")

        let migration = CredentialMigration(store: store, defaults: defaults)
        try migration.migrateIfNeeded(
            userDefaultsKey: "translator.apiKey",
            account: "default"
        )

        #expect(try store.read(account: "default") == "already-migrated")
        #expect(defaults.string(forKey: "translator.apiKey") == nil)
    }

    @Test("migration is no-op when UserDefaults has no value")
    func noopWhenAbsent() throws {
        let store = makeStore()
        let defaults = makeDefaults()
        defer { try? store.delete(account: "default") }

        let migration = CredentialMigration(store: store, defaults: defaults)
        try migration.migrateIfNeeded(
            userDefaultsKey: "translator.apiKey",
            account: "default"
        )

        #expect(try store.read(account: "default") == nil)
    }
}

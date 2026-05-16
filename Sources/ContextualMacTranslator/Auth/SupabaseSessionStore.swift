import Foundation

/// Persistence boundary for the Supabase session. Protocol so tests can
/// inject an in-memory double instead of touching the real Keychain.
protocol SupabaseSessionStoring: Sendable {
    func load() -> SupabaseSession?
    func save(_ session: SupabaseSession)
    func clear()
}

/// Keychain-backed session store. The session is JSON-encoded and written
/// as a single generic-password item, matching how the app already stores
/// other secrets (`KeychainCredentialStore`).
struct KeychainSupabaseSessionStore: SupabaseSessionStoring {
    /// Keychain account for the encoded session blob.
    static let account = "supabase-session"

    private let keychain: KeychainCredentialStore

    init(keychain: KeychainCredentialStore) {
        self.keychain = keychain
    }

    func load() -> SupabaseSession? {
        guard let json = try? keychain.read(account: Self.account),
              let data = json.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder.supabase.decode(SupabaseSession.self, from: data)
    }

    func save(_ session: SupabaseSession) {
        guard let data = try? JSONEncoder.supabase.encode(session),
              let json = String(data: data, encoding: .utf8) else {
            return
        }
        try? keychain.write(json, account: Self.account)
    }

    func clear() {
        try? keychain.delete(account: Self.account)
    }
}

/// In-memory store for tests + previews. Not persisted.
final class InMemorySupabaseSessionStore: SupabaseSessionStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var session: SupabaseSession?

    init(initial: SupabaseSession? = nil) {
        self.session = initial
    }

    func load() -> SupabaseSession? {
        lock.lock(); defer { lock.unlock() }
        return session
    }

    func save(_ session: SupabaseSession) {
        lock.lock(); defer { lock.unlock() }
        self.session = session
    }

    func clear() {
        lock.lock(); defer { lock.unlock() }
        session = nil
    }
}

extension JSONEncoder {
    /// Shared encoder for Supabase payloads — ISO-8601 dates.
    static var supabase: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    /// Shared decoder for Supabase payloads — ISO-8601 dates.
    static var supabase: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

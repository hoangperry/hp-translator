import Foundation
import Testing

@testable import ContextualMacTranslator

// MARK: - Local URLProtocol stub

/// Routes stubbed responses by request path so one session can serve the
/// otp / verify / token endpoints in a single test.
final class SupabaseStubProtocol: URLProtocol, @unchecked Sendable {
    /// path-suffix → (status, json body)
    nonisolated(unsafe) static var routes: [String: (Int, String)] = [:]
    nonisolated(unsafe) static var capturedPaths: [String] = []

    static func reset() {
        routes = [:]
        capturedPaths = []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let path = request.url?.path ?? ""
        Self.capturedPaths.append(path)
        let match = Self.routes.first { path.hasSuffix($0.key) }?.value ?? (404, "{}")
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: match.0,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(match.1.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func stubbedSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [SupabaseStubProtocol.self]
    return URLSession(configuration: config)
}

private let testConfig = SupabaseAuthConfig(
    baseURL: URL(string: "https://stub.supabase.co")!,
    anonKey: "anon-test-key"
)

private func sessionJSON(
    accessToken: String,
    refreshToken: String,
    expiresAt: Double,
    email: String = "[email protected]"
) -> String {
    """
    {
      "access_token": "\(accessToken)",
      "refresh_token": "\(refreshToken)",
      "token_type": "bearer",
      "expires_at": \(Int(expiresAt)),
      "user": { "email": "\(email)" }
    }
    """
}

// MARK: - Session model

@Suite("SupabaseSession")
struct SupabaseSessionTests {
    @Test("isFresh true when expiry comfortably ahead")
    func freshWhenAhead() {
        let s = SupabaseSession(
            accessToken: "a", refreshToken: "r",
            expiresAt: Date().addingTimeInterval(600), userEmail: nil
        )
        #expect(s.isFresh)
    }

    @Test("isFresh false within the 60s refresh window")
    func staleWithinWindow() {
        let s = SupabaseSession(
            accessToken: "a", refreshToken: "r",
            expiresAt: Date().addingTimeInterval(30), userEmail: nil
        )
        #expect(!s.isFresh)
    }

    @Test("isFresh false when already expired")
    func staleWhenExpired() {
        let s = SupabaseSession(
            accessToken: "a", refreshToken: "r",
            expiresAt: Date().addingTimeInterval(-10), userEmail: nil
        )
        #expect(!s.isFresh)
    }
}

@Suite("BackendAuthMode")
struct BackendAuthModeTests {
    @Test("both modes have distinct display names")
    func displayNames() {
        #expect(BackendAuthMode.selfHostStaticToken.displayName != BackendAuthMode.saasSupabaseSession.displayName)
    }

    @Test("round-trips through raw value")
    func rawValueRoundTrip() {
        for mode in BackendAuthMode.allCases {
            #expect(BackendAuthMode(rawValue: mode.rawValue) == mode)
        }
    }
}

// MARK: - Session store

@Suite("InMemorySupabaseSessionStore")
struct SessionStoreTests {
    @Test("save then load round-trips")
    func roundTrip() {
        let store = InMemorySupabaseSessionStore()
        let s = SupabaseSession(
            accessToken: "a", refreshToken: "r",
            expiresAt: Date(timeIntervalSince1970: 1_000_000), userEmail: "[email protected]"
        )
        store.save(s)
        #expect(store.load() == s)
    }

    @Test("clear removes the session")
    func clearRemoves() {
        let store = InMemorySupabaseSessionStore(initial: SupabaseSession(
            accessToken: "a", refreshToken: "r", expiresAt: Date(), userEmail: nil
        ))
        store.clear()
        #expect(store.load() == nil)
    }
}

// MARK: - Auth service

/// Serialized: `SupabaseStubProtocol.routes` is process-global mutable
/// state; parallel cases would race each other's route table.
@Suite("SupabaseAuthService", .serialized)
struct SupabaseAuthServiceTests {
    @Test("sendOTP succeeds on 2xx")
    func sendOTPSuccess() async throws {
        SupabaseStubProtocol.reset()
        SupabaseStubProtocol.routes = ["/auth/v1/otp": (200, "{}")]
        let service = SupabaseAuthService(
            config: testConfig, session: stubbedSession(),
            store: InMemorySupabaseSessionStore()
        )
        try await service.sendOTP(email: "[email protected]")
        #expect(SupabaseStubProtocol.capturedPaths.contains { $0.hasSuffix("/auth/v1/otp") })
    }

    @Test("sendOTP throws otpSendFailed on 4xx")
    func sendOTPFailure() async throws {
        SupabaseStubProtocol.reset()
        SupabaseStubProtocol.routes = ["/auth/v1/otp": (422, "{\"error\":\"bad\"}")]
        let service = SupabaseAuthService(
            config: testConfig, session: stubbedSession(),
            store: InMemorySupabaseSessionStore()
        )
        await #expect(throws: SupabaseAuthError.otpSendFailed(status: 422)) {
            try await service.sendOTP(email: "[email protected]")
        }
    }

    @Test("operations throw notConfigured when anon key empty")
    func notConfigured() async throws {
        let service = SupabaseAuthService(
            config: SupabaseAuthConfig(baseURL: testConfig.baseURL, anonKey: ""),
            session: stubbedSession(),
            store: InMemorySupabaseSessionStore()
        )
        await #expect(throws: SupabaseAuthError.notConfigured) {
            try await service.sendOTP(email: "[email protected]")
        }
    }

    @Test("verifyOTP stores a session on success")
    func verifySuccess() async throws {
        SupabaseStubProtocol.reset()
        let future = Date().addingTimeInterval(3600).timeIntervalSince1970
        SupabaseStubProtocol.routes = [
            "/auth/v1/verify": (200, sessionJSON(
                accessToken: "access-1", refreshToken: "refresh-1", expiresAt: future
            )),
        ]
        let store = InMemorySupabaseSessionStore()
        let service = SupabaseAuthService(
            config: testConfig, session: stubbedSession(), store: store
        )
        try await service.verifyOTP(email: "[email protected]", code: "123456")

        let connected = await service.isConnected
        #expect(connected)
        #expect(store.load()?.accessToken == "access-1")
        #expect(store.load()?.userEmail == "[email protected]")
    }

    @Test("verifyOTP throws verificationFailed on wrong code")
    func verifyWrongCode() async throws {
        SupabaseStubProtocol.reset()
        SupabaseStubProtocol.routes = ["/auth/v1/verify": (403, "{\"error\":\"invalid\"}")]
        let service = SupabaseAuthService(
            config: testConfig, session: stubbedSession(),
            store: InMemorySupabaseSessionStore()
        )
        await #expect(throws: SupabaseAuthError.verificationFailed(status: 403)) {
            try await service.verifyOTP(email: "[email protected]", code: "000000")
        }
    }

    @Test("verifyOTP throws malformedResponse when body lacks tokens")
    func verifyMalformed() async throws {
        SupabaseStubProtocol.reset()
        SupabaseStubProtocol.routes = ["/auth/v1/verify": (200, "{\"unexpected\":true}")]
        let service = SupabaseAuthService(
            config: testConfig, session: stubbedSession(),
            store: InMemorySupabaseSessionStore()
        )
        await #expect(throws: SupabaseAuthError.malformedResponse) {
            try await service.verifyOTP(email: "[email protected]", code: "123456")
        }
    }

    @Test("currentAccessToken throws noSession when not connected")
    func tokenNoSession() async throws {
        let service = SupabaseAuthService(
            config: testConfig, session: stubbedSession(),
            store: InMemorySupabaseSessionStore()
        )
        await #expect(throws: SupabaseAuthError.noSession) {
            _ = try await service.currentAccessToken()
        }
    }

    @Test("currentAccessToken returns stored token when fresh — no refresh call")
    func tokenFreshNoRefresh() async throws {
        SupabaseStubProtocol.reset()
        let fresh = SupabaseSession(
            accessToken: "still-good", refreshToken: "r",
            expiresAt: Date().addingTimeInterval(600), userEmail: "[email protected]"
        )
        let service = SupabaseAuthService(
            config: testConfig, session: stubbedSession(),
            store: InMemorySupabaseSessionStore(initial: fresh)
        )
        let token = try await service.currentAccessToken()
        #expect(token == "still-good")
        #expect(SupabaseStubProtocol.capturedPaths.isEmpty)
    }

    @Test("currentAccessToken refreshes a stale session")
    func tokenRefreshesStale() async throws {
        SupabaseStubProtocol.reset()
        let future = Date().addingTimeInterval(3600).timeIntervalSince1970
        SupabaseStubProtocol.routes = [
            "/auth/v1/token": (200, sessionJSON(
                accessToken: "access-2", refreshToken: "refresh-2", expiresAt: future
            )),
        ]
        let stale = SupabaseSession(
            accessToken: "expired", refreshToken: "refresh-1",
            expiresAt: Date().addingTimeInterval(-10), userEmail: "[email protected]"
        )
        let store = InMemorySupabaseSessionStore(initial: stale)
        let service = SupabaseAuthService(
            config: testConfig, session: stubbedSession(), store: store
        )
        let token = try await service.currentAccessToken()
        #expect(token == "access-2")
        // refreshed session persisted
        #expect(store.load()?.refreshToken == "refresh-2")
        #expect(SupabaseStubProtocol.capturedPaths.contains { $0.hasSuffix("/auth/v1/token") })
    }

    @Test("currentAccessToken throws refreshFailed when refresh rejected")
    func tokenRefreshRejected() async throws {
        SupabaseStubProtocol.reset()
        SupabaseStubProtocol.routes = ["/auth/v1/token": (400, "{\"error\":\"invalid_grant\"}")]
        let stale = SupabaseSession(
            accessToken: "expired", refreshToken: "dead",
            expiresAt: Date().addingTimeInterval(-10), userEmail: nil
        )
        let service = SupabaseAuthService(
            config: testConfig, session: stubbedSession(),
            store: InMemorySupabaseSessionStore(initial: stale)
        )
        await #expect(throws: SupabaseAuthError.refreshFailed(status: 400)) {
            _ = try await service.currentAccessToken()
        }
    }

    @Test("signOut clears local + persisted session")
    func signOutClears() async throws {
        let store = InMemorySupabaseSessionStore(initial: SupabaseSession(
            accessToken: "a", refreshToken: "r",
            expiresAt: Date().addingTimeInterval(600), userEmail: nil
        ))
        let service = SupabaseAuthService(
            config: testConfig, session: stubbedSession(), store: store
        )
        await service.signOut()
        let connected = await service.isConnected
        #expect(!connected)
        #expect(store.load() == nil)
    }

    @Test("service restores an existing session from the store on init")
    func restoresFromStore() async throws {
        let stored = SupabaseSession(
            accessToken: "restored", refreshToken: "r",
            expiresAt: Date().addingTimeInterval(600), userEmail: "[email protected]"
        )
        let service = SupabaseAuthService(
            config: testConfig, session: stubbedSession(),
            store: InMemorySupabaseSessionStore(initial: stored)
        )
        let connected = await service.isConnected
        let email = await service.connectedEmail
        #expect(connected)
        #expect(email == "[email protected]")
    }
}

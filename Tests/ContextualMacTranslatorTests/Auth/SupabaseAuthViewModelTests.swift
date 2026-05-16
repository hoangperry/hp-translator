import Foundation
import Testing

@testable import ContextualMacTranslator

// MARK: - Dedicated stub (own static state — isolated from other auth tests)

final class VMAuthStubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var routes: [String: (Int, String)] = [:]

    static func reset() { routes = [:] }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let path = request.url?.path ?? ""
        let match = Self.routes.first { path.hasSuffix($0.key) }?.value ?? (404, "{}")
        let response = HTTPURLResponse(
            url: request.url!, statusCode: match.0, httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(match.1.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@MainActor
private func makeViewModel(
    configured: Bool = true
) -> (SupabaseAuthViewModel, SettingsStore) {
    let suite = "vm-tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    let settings = SettingsStore(
        defaults: defaults,
        keychain: KeychainCredentialStore(service: "vm-tests.\(UUID().uuidString)")
    )
    if configured {
        settings.supabaseURL = "https://stub.supabase.co"
        settings.supabaseAnonKey = "anon-key"
    }
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [VMAuthStubProtocol.self]
    let vm = SupabaseAuthViewModel(
        settings: settings,
        urlSession: URLSession(configuration: config)
    )
    return (vm, settings)
}

private func sessionJSON(email: String = "[email protected]") -> String {
    let future = Int(Date().addingTimeInterval(3600).timeIntervalSince1970)
    return """
    {"access_token":"a","refresh_token":"r","expires_at":\(future),"user":{"email":"\(email)"}}
    """
}

// MARK: - Pure logic (no network)

@Suite("SupabaseAuthViewModel — input validation")
@MainActor
struct SupabaseAuthViewModelValidationTests {
    @Test("sendCode with empty email → error phase")
    func emptyEmail() async {
        let (vm, _) = makeViewModel()
        vm.emailInput = "   "
        await vm.sendCode()
        guard case .error = vm.phase else {
            Issue.record("expected .error, got \(vm.phase)")
            return
        }
    }

    @Test("sendCode with no Supabase config → error phase")
    func noConfig() async {
        let (vm, _) = makeViewModel(configured: false)
        vm.emailInput = "[email protected]"
        await vm.sendCode()
        guard case .error = vm.phase else {
            Issue.record("expected .error, got \(vm.phase)")
            return
        }
    }

    @Test("verify outside codeSent phase is a no-op")
    func verifyWrongPhase() async {
        let (vm, _) = makeViewModel()
        // phase is .idle
        await vm.verify()
        #expect(vm.phase == .idle)
    }
}

// MARK: - Network-backed flow

@Suite("SupabaseAuthViewModel — OTP flow", .serialized)
@MainActor
struct SupabaseAuthViewModelFlowTests {
    @Test("sendCode success moves to codeSent")
    func sendCodeSuccess() async {
        VMAuthStubProtocol.reset()
        VMAuthStubProtocol.routes = ["/auth/v1/otp": (200, "{}")]
        let (vm, _) = makeViewModel()
        vm.emailInput = "[email protected]"
        await vm.sendCode()
        #expect(vm.phase == .codeSent(email: "[email protected]"))
    }

    @Test("sendCode failure moves to error")
    func sendCodeFailure() async {
        VMAuthStubProtocol.reset()
        VMAuthStubProtocol.routes = ["/auth/v1/otp": (422, "{}")]
        let (vm, _) = makeViewModel()
        vm.emailInput = "[email protected]"
        await vm.sendCode()
        guard case .error = vm.phase else {
            Issue.record("expected .error, got \(vm.phase)")
            return
        }
    }

    @Test("full flow: send → verify → connected")
    func fullFlow() async {
        VMAuthStubProtocol.reset()
        VMAuthStubProtocol.routes = [
            "/auth/v1/otp": (200, "{}"),
            "/auth/v1/verify": (200, sessionJSON(email: "[email protected]")),
        ]
        let (vm, _) = makeViewModel()
        vm.emailInput = "[email protected]"
        await vm.sendCode()
        #expect(vm.phase == .codeSent(email: "[email protected]"))

        vm.codeInput = "123456"
        await vm.verify()
        #expect(vm.phase == .connected(email: "[email protected]"))
    }

    @Test("verify with empty code → error")
    func verifyEmptyCode() async {
        VMAuthStubProtocol.reset()
        VMAuthStubProtocol.routes = ["/auth/v1/otp": (200, "{}")]
        let (vm, _) = makeViewModel()
        vm.emailInput = "[email protected]"
        await vm.sendCode()
        vm.codeInput = ""
        await vm.verify()
        guard case .error = vm.phase else {
            Issue.record("expected .error, got \(vm.phase)")
            return
        }
    }

    @Test("verify with wrong code → error")
    func verifyWrongCode() async {
        VMAuthStubProtocol.reset()
        VMAuthStubProtocol.routes = [
            "/auth/v1/otp": (200, "{}"),
            "/auth/v1/verify": (403, "{}"),
        ]
        let (vm, _) = makeViewModel()
        vm.emailInput = "[email protected]"
        await vm.sendCode()
        vm.codeInput = "000000"
        await vm.verify()
        guard case .error = vm.phase else {
            Issue.record("expected .error, got \(vm.phase)")
            return
        }
    }

    @Test("signOut returns to idle and clears inputs")
    func signOut() async {
        VMAuthStubProtocol.reset()
        VMAuthStubProtocol.routes = [
            "/auth/v1/otp": (200, "{}"),
            "/auth/v1/verify": (200, sessionJSON()),
        ]
        let (vm, _) = makeViewModel()
        vm.emailInput = "[email protected]"
        await vm.sendCode()
        vm.codeInput = "123456"
        await vm.verify()

        await vm.signOut()
        #expect(vm.phase == .idle)
        #expect(vm.emailInput.isEmpty)
        #expect(vm.codeInput.isEmpty)
    }

    @Test("refreshConnectionState reflects a persisted session")
    func refreshReflectsSession() async {
        VMAuthStubProtocol.reset()
        VMAuthStubProtocol.routes = [
            "/auth/v1/otp": (200, "{}"),
            "/auth/v1/verify": (200, sessionJSON(email: "[email protected]")),
        ]
        let (vm, settings) = makeViewModel()
        // Connect once to write a session into the (shared) Keychain store.
        vm.emailInput = "[email protected]"
        await vm.sendCode()
        vm.codeInput = "123456"
        await vm.verify()

        // A fresh view model over the same settings should see the session.
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [VMAuthStubProtocol.self]
        let fresh = SupabaseAuthViewModel(
            settings: settings,
            urlSession: URLSession(configuration: config)
        )
        await fresh.refreshConnectionState()
        #expect(fresh.phase == .connected(email: "[email protected]"))
    }
}

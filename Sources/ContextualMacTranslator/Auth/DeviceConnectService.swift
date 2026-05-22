import AppKit
import CryptoKit
import Foundation
import OSLog

/// One-click "Connect with contextmt.dev" pairing flow.
///
/// Steps:
///   1. Generate a PKCE verifier + challenge and a random `state`.
///   2. Start a loopback server; open the browser at the `/connect` page.
///   3. The user clicks "Authorize" on the web page (already signed in).
///   4. The browser redirects the one-time pairing code back to loopback.
///   5. Exchange the code (+ PKCE verifier) at `connect-claim` for a fresh,
///      independent Supabase session — persisted to the Keychain.
///
/// The app never types an email or code; the web page owns sign-in.
actor DeviceConnectService {
    enum ConnectError: Error, LocalizedError {
        case notConfigured
        case loopbackFailed
        case browserOpenFailed
        case timedOut
        case stateMismatch
        case userCancelled
        case claimFailed(status: Int)
        case malformedResponse
        case transport(String)

        var errorDescription: String? {
            switch self {
            case .notConfigured:
                return "Cloud backend is not configured."
            case .loopbackFailed:
                return "Could not start the local sign-in listener."
            case .browserOpenFailed:
                return "Could not open the browser."
            case .timedOut:
                return "Sign-in timed out. Please try again."
            case .stateMismatch:
                return "Sign-in response did not match this request."
            case .userCancelled:
                return "Sign-in was cancelled."
            case .claimFailed:
                return "The pairing code was rejected. Please try again."
            case .malformedResponse:
                return "Unexpected response from the cloud backend."
            case .transport(let detail):
                return "Network error: \(detail)"
            }
        }
    }

    private let config: SupabaseAuthConfig
    private let dashboardURL: URL
    private let store: any SupabaseSessionStoring
    private let session: URLSession
    private let now: @Sendable () -> Date
    private let logger = Logger(subsystem: "app.lookerlab.translator", category: "device-connect")

    /// How long to wait for the user to finish in the browser.
    private let timeout: TimeInterval = 300

    init(
        config: SupabaseAuthConfig,
        dashboardURL: URL,
        store: any SupabaseSessionStoring,
        session: URLSession = .shared,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.config = config
        self.dashboardURL = dashboardURL
        self.store = store
        self.session = session
        self.now = now
    }

    /// Run the full flow. Returns the connected account email.
    func connect() async throws -> String {
        guard config.isConfigured else { throw ConnectError.notConfigured }

        let verifier = Self.randomURLSafe(byteCount: 32)
        let challenge = Self.sha256Base64URL(verifier)
        let state = Self.randomURLSafe(byteCount: 16)

        let server: LoopbackCallbackServer
        do {
            server = try LoopbackCallbackServer()
        } catch {
            throw ConnectError.loopbackFailed
        }

        let port: UInt16
        do {
            port = try await server.start()
        } catch {
            throw ConnectError.loopbackFailed
        }
        defer { server.stop() }

        // Open the browser at the authorize page.
        let connectURL = makeConnectURL(port: port, state: state, challenge: challenge)
        guard await openInBrowser(connectURL) else {
            throw ConnectError.browserOpenFailed
        }

        // Await the loopback callback, bounded by `timeout`.
        let query = try await withTimeout(timeout) {
            try await server.waitForCallback()
        }

        guard let returnedState = query["state"], returnedState == state else {
            throw ConnectError.stateMismatch
        }
        guard let code = query["code"], !code.isEmpty else {
            throw ConnectError.userCancelled
        }

        let session = try await claim(pairingCode: code, verifier: verifier)
        store.save(session)
        return session.userEmail ?? ""
    }

    // MARK: - Claim

    private func claim(pairingCode: String, verifier: String) async throws -> SupabaseSession {
        let url = config.baseURL.appendingPathComponent("/functions/v1/connect-claim")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "pairing_code": pairingCode,
            "code_verifier": verifier,
        ])

        let data: Data
        let status: Int
        do {
            let (body, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw ConnectError.malformedResponse
            }
            data = body
            status = http.statusCode
        } catch let error as ConnectError {
            throw error
        } catch {
            throw ConnectError.transport((error as? URLError)?.localizedDescription
                ?? error.localizedDescription)
        }

        guard (200...299).contains(status) else {
            logger.error("connect-claim failed: HTTP \(status)")
            throw ConnectError.claimFailed(status: status)
        }

        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = object["access_token"] as? String,
              let refreshToken = object["refresh_token"] as? String else {
            throw ConnectError.malformedResponse
        }
        let expiresAt: Date
        if let absolute = object["expires_at"] as? Double {
            expiresAt = Date(timeIntervalSince1970: absolute)
        } else if let relative = object["expires_in"] as? Double {
            expiresAt = now().addingTimeInterval(relative)
        } else {
            throw ConnectError.malformedResponse
        }
        return SupabaseSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt,
            userEmail: object["email"] as? String
        )
    }

    // MARK: - URL + browser

    private func makeConnectURL(port: UInt16, state: String, challenge: String) -> URL {
        var components = URLComponents(
            url: dashboardURL.appendingPathComponent("/connect"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "cb", value: "http://127.0.0.1:\(port)/cb"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "challenge", value: challenge),
        ]
        return components?.url ?? dashboardURL
    }

    @MainActor
    private func openInBrowser(_ url: URL) -> Bool {
        NSWorkspace.shared.open(url)
    }

    // MARK: - Crypto helpers

    /// Random base64url string (no padding) — used for the PKCE verifier
    /// and the CSRF `state`. `byteCount` 32 → 43 chars; 16 → 22 chars.
    private static func randomURLSafe(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        _ = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        return Data(bytes).base64URLEncodedString()
    }

    /// base64url(SHA-256(input)) — the PKCE S256 challenge.
    private static func sha256Base64URL(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return Data(digest).base64URLEncodedString()
    }

    // MARK: - Timeout

    private func withTimeout<T: Sendable>(
        _ seconds: TimeInterval,
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw ConnectError.timedOut
            }
            guard let result = try await group.next() else {
                throw ConnectError.timedOut
            }
            group.cancelAll()
            return result
        }
    }
}

extension Data {
    /// base64url encoding without padding (RFC 4648 §5).
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

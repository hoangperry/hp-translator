import Foundation
import OSLog

/// Connection config for Contextual MT Cloud. Both values are public by
/// design — the anon key is meant to be embedded in clients; row-level
/// security protects data server-side.
struct SupabaseAuthConfig: Equatable, Sendable {
    let baseURL: URL
    let anonKey: String

    var isConfigured: Bool {
        !anonKey.isEmpty
    }
}

/// Hand-rolled GoTrue (Supabase Auth) client for email-OTP sign-in.
///
/// Scope is deliberately narrow — exactly the three endpoints a desktop
/// app needs:
///   - `POST /auth/v1/otp`     send a 6-digit code by email
///   - `POST /auth/v1/verify`  exchange the code for a session
///   - `POST /auth/v1/token`   refresh-token grant
///
/// We do NOT pull in `supabase-swift`: the client side of token handling is
/// small (hold the latest refresh token, exchange before expiry) and the
/// SDK's session-persistence adapter would fight our Keychain store. The
/// hard part — refresh-token rotation + reuse detection — is server-side
/// and stays with Supabase.
///
/// An actor: it owns the mutable `current` session and serializes refresh
/// so two concurrent translations can't double-refresh.
actor SupabaseAuthService {
    private let config: SupabaseAuthConfig
    private let session: URLSession
    private let store: any SupabaseSessionStoring
    private let now: @Sendable () -> Date
    private let logger = Logger(subsystem: "app.lookerlab.translator", category: "supabase-auth")

    private var current: SupabaseSession?

    init(
        config: SupabaseAuthConfig,
        session: URLSession = .shared,
        store: any SupabaseSessionStoring,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.config = config
        self.session = session
        self.store = store
        self.now = now
        self.current = store.load()
    }

    // MARK: - State

    /// `true` once a session is stored (may still be expired — call
    /// `currentAccessToken()` to get a guaranteed-fresh token).
    var isConnected: Bool { current != nil }

    /// Email of the connected account, if known.
    var connectedEmail: String? { current?.userEmail }

    // MARK: - OTP sign-in

    /// Request a one-time code be emailed to `email`. The Supabase project's
    /// email template must use `{{ .Token }}` so the user receives a code
    /// rather than a magic link (see docs/SUPABASE-DEPLOYMENT.md).
    func sendOTP(email: String) async throws {
        guard config.isConfigured else { throw SupabaseAuthError.notConfigured }
        let body = try JSONSerialization.data(withJSONObject: ["email": email])
        let request = makeRequest(path: "/auth/v1/otp", body: body)
        let status = try await statusCode(for: request)
        guard (200...299).contains(status) else {
            logger.error("OTP send failed: HTTP \(status)")
            throw SupabaseAuthError.otpSendFailed(status: status)
        }
    }

    /// Exchange an emailed code for a session. On success the session is
    /// persisted and becomes the active session.
    func verifyOTP(email: String, code: String) async throws {
        guard config.isConfigured else { throw SupabaseAuthError.notConfigured }
        let body = try JSONSerialization.data(withJSONObject: [
            "type": "email",
            "email": email,
            "token": code,
        ])
        let request = makeRequest(path: "/auth/v1/verify", body: body)
        let (data, status) = try await dataAndStatus(for: request)
        guard (200...299).contains(status) else {
            logger.error("OTP verify failed: HTTP \(status)")
            throw SupabaseAuthError.verificationFailed(status: status)
        }
        let session = try decodeSession(from: data, fallbackEmail: email)
        current = session
        store.save(session)
    }

    // MARK: - Token access

    /// Return a guaranteed-fresh access token, refreshing transparently when
    /// the current one is within 60s of expiry. Throws `noSession` if the
    /// user has not connected, `refreshFailed` if the refresh token is dead.
    func currentAccessToken() async throws -> String {
        guard let session = current else { throw SupabaseAuthError.noSession }
        if session.expiresAt.timeIntervalSince(now()) > 60 {
            return session.accessToken
        }
        let refreshed = try await refresh(using: session.refreshToken)
        current = refreshed
        store.save(refreshed)
        return refreshed.accessToken
    }

    /// Drop the local session. Does not revoke server-side — that is the
    /// dashboard's "revoke device" action.
    func signOut() {
        current = nil
        store.clear()
    }

    // MARK: - Refresh

    private func refresh(using refreshToken: String) async throws -> SupabaseSession {
        let body = try JSONSerialization.data(withJSONObject: ["refresh_token": refreshToken])
        let request = makeRequest(
            path: "/auth/v1/token",
            query: [URLQueryItem(name: "grant_type", value: "refresh_token")],
            body: body
        )
        let (data, status) = try await dataAndStatus(for: request)
        guard (200...299).contains(status) else {
            logger.error("Refresh failed: HTTP \(status)")
            throw SupabaseAuthError.refreshFailed(status: status)
        }
        return try decodeSession(from: data, fallbackEmail: current?.userEmail)
    }

    // MARK: - HTTP plumbing

    private func makeRequest(
        path: String,
        query: [URLQueryItem] = [],
        body: Data
    ) -> URLRequest {
        var components = URLComponents(
            url: config.baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )
        if !query.isEmpty { components?.queryItems = query }
        // baseURL + path is always a valid URL; the force is documented.
        let url = components?.url ?? config.baseURL.appendingPathComponent(path)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.httpBody = body
        return request
    }

    private func dataAndStatus(for request: URLRequest) async throws -> (Data, Int) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw SupabaseAuthError.malformedResponse
            }
            return (data, http.statusCode)
        } catch let error as SupabaseAuthError {
            throw error
        } catch {
            throw SupabaseAuthError.transport((error as? URLError)?.code.rawValue.description
                ?? error.localizedDescription)
        }
    }

    private func statusCode(for request: URLRequest) async throws -> Int {
        try await dataAndStatus(for: request).1
    }

    private func decodeSession(from data: Data, fallbackEmail: String?) throws -> SupabaseSession {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = object["access_token"] as? String,
              let refreshToken = object["refresh_token"] as? String else {
            throw SupabaseAuthError.malformedResponse
        }
        let expiresAt: Date
        if let absolute = object["expires_at"] as? Double {
            expiresAt = Date(timeIntervalSince1970: absolute)
        } else if let relative = object["expires_in"] as? Double {
            expiresAt = now().addingTimeInterval(relative)
        } else {
            // GoTrue always sends one of the two; treat absence as malformed.
            throw SupabaseAuthError.malformedResponse
        }
        let user = object["user"] as? [String: Any]
        let email = (user?["email"] as? String) ?? fallbackEmail
        return SupabaseSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt,
            userEmail: email
        )
    }
}

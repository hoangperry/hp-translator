import Foundation

/// A Supabase Auth session obtained via email-OTP sign-in.
///
/// Persisted (JSON) in the Keychain. The access token is short-lived
/// (`jwt_expiry = 900` on the backend); the refresh token rotates and is
/// used to mint a fresh access token before expiry.
struct SupabaseSession: Codable, Equatable, Sendable {
    let accessToken: String
    let refreshToken: String
    /// Absolute expiry of `accessToken`.
    let expiresAt: Date
    /// Email the session was issued for — shown in Settings, may be nil if
    /// the verify response omitted the user object.
    let userEmail: String?

    /// `true` while the access token has comfortable runway left. We refresh
    /// proactively at 60s remaining so an in-flight translation never races
    /// expiry.
    var isFresh: Bool {
        expiresAt.timeIntervalSinceNow > 60
    }
}

/// Auth-mode selector for `BackendProvider`. Self-host keeps the M1
/// static-token behavior; SaaS uses a refreshable Supabase session.
enum BackendAuthMode: String, Codable, CaseIterable, Sendable {
    /// M1 — user-managed `translator-server`, static bearer token.
    case selfHostStaticToken
    /// M2 — Contextual MT Cloud, Supabase email-OTP session.
    case saasSupabaseSession

    var displayName: String {
        switch self {
        case .selfHostStaticToken: return "Self-hosted backend"
        case .saasSupabaseSession: return "Contextual MT Cloud"
        }
    }
}

/// Errors surfaced by `SupabaseAuthService`. Equatable so tests can assert
/// on the exact failure without string matching. `LocalizedError` so a
/// translation that fails on auth shows the actionable `userMessage` in the
/// HUD instead of a generic Cocoa error string.
enum SupabaseAuthError: Error, Equatable, LocalizedError {
    /// Project URL / anon key not configured.
    case notConfigured
    /// OTP email send rejected by GoTrue.
    case otpSendFailed(status: Int)
    /// Code verification rejected (wrong / expired code).
    case verificationFailed(status: Int)
    /// Refresh-token exchange rejected — session is dead, user must re-auth.
    case refreshFailed(status: Int)
    /// An operation needs a session but none is stored.
    case noSession
    /// Server returned 2xx but the body was not the expected shape.
    case malformedResponse
    /// Transport-level failure (offline, DNS, TLS).
    case transport(String)

    var userMessage: String {
        switch self {
        case .notConfigured:
            return "Cloud backend is not configured yet."
        case .otpSendFailed:
            return "Could not send the sign-in code. Check the email and try again."
        case .verificationFailed:
            return "That code is wrong or expired. Request a new one."
        case .refreshFailed:
            return "Your cloud session expired. Please sign in again."
        case .noSession:
            return "You are not signed in to Contextual MT Cloud."
        case .malformedResponse:
            return "Unexpected response from the cloud backend."
        case .transport(let detail):
            return "Network error reaching the cloud backend: \(detail)"
        }
    }

    /// `LocalizedError` — surfaces `userMessage` through `localizedDescription`.
    var errorDescription: String? { userMessage }
}

import Foundation
import Observation

/// SwiftUI-facing view model for the "Connect to Cloud" OTP flow.
///
/// Bridges the `SupabaseAuthService` actor to a `@MainActor` `@Observable`
/// reference type the Settings panel can bind to via `@Bindable`. No service
/// instance is cached — each operation builds a fresh service that reads the
/// latest session from the shared Keychain store, exactly like
/// `TranslationProviderFactory`. The Keychain is the single source of truth.
@MainActor
@Observable
final class SupabaseAuthViewModel {
    /// UI state machine for the sign-in flow.
    enum Phase: Equatable {
        case idle
        case sending
        case codeSent(email: String)
        case verifying
        case connected(email: String)
        case error(String)
    }

    private(set) var phase: Phase = .idle
    var emailInput: String = ""
    var codeInput: String = ""

    private let settings: SettingsStore
    private let urlSession: URLSession

    init(settings: SettingsStore, urlSession: URLSession = .shared) {
        self.settings = settings
        self.urlSession = urlSession
    }

    /// Build a service from current settings config. `nil` when the project
    /// URL / anon key are not configured.
    private func makeService() -> SupabaseAuthService? {
        guard let config = settings.supabaseAuthConfig() else { return nil }
        return SupabaseAuthService(
            config: config,
            session: urlSession,
            store: settings.makeSupabaseSessionStore()
        )
    }

    /// Reflect the persisted session into `phase` — call on panel appear.
    func refreshConnectionState() async {
        guard let service = makeService() else {
            phase = .idle
            return
        }
        if await service.isConnected {
            phase = .connected(email: await service.connectedEmail ?? "")
        } else {
            phase = .idle
        }
    }

    /// Email a one-time code to `emailInput`.
    func sendCode() async {
        let email = emailInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.isEmpty else {
            phase = .error("Enter your email first.")
            return
        }
        guard let service = makeService() else {
            phase = .error("Set the Supabase project URL and anon key first.")
            return
        }
        phase = .sending
        do {
            try await service.sendOTP(email: email)
            codeInput = ""
            phase = .codeSent(email: email)
        } catch {
            phase = .error(Self.message(for: error))
        }
    }

    /// Exchange the entered code for a session.
    func verify() async {
        guard case let .codeSent(email) = phase else { return }
        let code = codeInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else {
            phase = .error("Enter the code from your email.")
            return
        }
        guard let service = makeService() else {
            phase = .error("Set the Supabase project URL and anon key first.")
            return
        }
        phase = .verifying
        do {
            try await service.verifyOTP(email: email, code: code)
            codeInput = ""
            phase = .connected(email: await service.connectedEmail ?? email)
        } catch {
            phase = .error(Self.message(for: error))
        }
    }

    /// Drop the local session.
    func signOut() async {
        await makeService()?.signOut()
        emailInput = ""
        codeInput = ""
        phase = .idle
    }

    private static func message(for error: Error) -> String {
        (error as? SupabaseAuthError)?.userMessage ?? error.localizedDescription
    }
}

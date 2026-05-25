import Foundation

/// Echo-only translator. Mirrors the Python `MockProvider` (`server.py`)
/// so smoke tests against the app produce the same `[<persona>] <text>`
/// output regardless of whether the translation went via direct mode or
/// via the backend.
@MainActor
final class MockDirectProvider: TranslationProvider {
    static var providerKey: String { "mock" }
    static var displayName: String { "Mock (echo)" }
    // Pure in-memory echo for tests + previews — nothing leaves the
    // process, classify as .local for HUD consistency.
    static var privacyClass: ProviderPrivacyClass { .local }

    var isConfigured: Bool { true }

    func translate(_ job: TranslationJob) async throws -> TranslationResult {
        TranslationResult(translation: "[\(job.style.rawValue)] \(job.text)")
    }
}

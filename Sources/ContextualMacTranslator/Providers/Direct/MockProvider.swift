import Foundation

/// Echo-only translator. Mirrors the Python `MockProvider` (`server.py`)
/// so smoke tests against the app produce the same `[<persona>] <text>`
/// output regardless of whether the translation went via direct mode or
/// via the backend.
@MainActor
final class MockDirectProvider: TranslationProvider {
    static var providerKey: String { "mock" }
    static var displayName: String { "Mock (echo)" }

    var isConfigured: Bool { true }

    func translate(_ job: TranslationJob) async throws -> TranslationResult {
        TranslationResult(translation: "[\(job.persona.rawValue)] \(job.text)")
    }
}

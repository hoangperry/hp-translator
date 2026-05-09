import Foundation

/// Common abstraction over every translation source — direct LLM/translate
/// API calls, custom self-hosted backend, or 1st-party hosted backend.
///
/// `TranslationWorkflow` is wired to a concrete provider via
/// `TranslationProviderFactory`. Switching the user's selection in Settings
/// changes the factory output without touching the workflow.
@MainActor
protocol TranslationProvider: AnyObject {
    /// Stable identifier used in Settings persistence + matches the
    /// `provider` field on the v2 API contract (when proxied via backend).
    static var providerKey: String { get }

    /// Human-readable label for the Settings UI.
    static var displayName: String { get }

    /// `true` when the provider has the credentials it needs to attempt a
    /// translation. False here surfaces `TranslationError.missingEndpoint`
    /// (or its provider-specific equivalent) early — before the workflow
    /// captures the clipboard, so the user can still copy/paste manually.
    var isConfigured: Bool { get }

    /// Translate one job. Throws `TranslationError` for known failure modes
    /// (network, auth, rate limit, ...). Other errors propagate verbatim.
    func translate(_ job: TranslationJob) async throws -> TranslationResult
}

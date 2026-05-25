import Foundation

/// v0.10.0 — where the OCR'd / typed / selected text actually goes when
/// a translation runs. Drives the Privacy badge in PreviewHUD + the
/// Settings → Privacy section ribbon.
enum ProviderPrivacyClass: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    /// Text never leaves the device. Ollama, on-device CLI providers.
    case local
    /// Text → 3rd-party API directly from the user's machine. Most direct
    /// providers (Gemini, OpenAI-compat, DeepL, Google Translate,
    /// LibreTranslate, CLI providers pointing at cloud models).
    case cloud
    /// Text → user's own / 1st-party backend (translator-server proxy,
    /// Supabase Edge Functions). User trust depends on who runs the host.
    case hosted

    /// Short label used inside the HUD badge.
    var badgeLabel: String {
        switch self {
        case .local:  return "Local"
        case .cloud:  return "Cloud"
        case .hosted: return "Hosted"
        }
    }

    /// Single emoji that travels with the badge — picked to be readable
    /// on both Liquid Glass (macOS 26) and the older opaque HUD.
    var badgeSymbol: String {
        switch self {
        case .local:  return "🛡"
        case .cloud:  return "☁"
        case .hosted: return "🏢"
        }
    }
}

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

    /// v0.10.0 — where text goes when this provider runs a translation.
    /// Default `.cloud` so adding a new provider without explicit
    /// classification fails-safe to the more conservative privacy
    /// posture (better to over-warn than to silently leak). Each
    /// concrete provider overrides with its true class.
    static var privacyClass: ProviderPrivacyClass { get }

    /// `true` when the provider has the credentials it needs to attempt a
    /// translation. False here surfaces `TranslationError.missingEndpoint`
    /// (or its provider-specific equivalent) early — before the workflow
    /// captures the clipboard, so the user can still copy/paste manually.
    var isConfigured: Bool { get }

    /// Translate one job. Throws `TranslationError` for known failure modes
    /// (network, auth, rate limit, ...). Other errors propagate verbatim.
    func translate(_ job: TranslationJob) async throws -> TranslationResult
}

extension TranslationProvider {
    /// Conservative default so a future provider added without thinking
    /// about privacy gets the louder badge by accident. Override on each
    /// concrete provider with the correct class.
    static var privacyClass: ProviderPrivacyClass { .cloud }
}

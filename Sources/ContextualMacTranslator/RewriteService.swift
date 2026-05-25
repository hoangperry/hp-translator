import Foundation

/// Provider-facing rewrite primitives extracted from `TranslationWorkflow`
/// in v0.9.1 to keep the workflow file under the 800-line guideline.
///
/// Owns:
///   • `rewrite(text:style:)` — single-shot rewrite with the v0.7
///     refusal-retry chain.
///   • `rewriteVariants(text:style:)` — v0.8.5 multi-variant entry;
///     asks the model for N drafts in one round-trip, parses the
///     sentinel-separated response, falls back to single-draft when
///     parsing yields <2 usable variants.
///   • `translateHeadless(text:targetLanguage:)` — App Intents bypass
///     of HUD/clipboard/keystrokes (v0.9.0).
///   • `rewriteHeadless(text:tone:)` + `rewriteHeadless(text:instruction:)`
///     — App Intents preset-tone / freetext rewrites.
///   • `style(forPickerEntry:language:)` — static helper that maps a
///     `PickerEntry` (freetext / preset / binding) → `TranslationStyle`.
///
/// Pure behaviour preservation — the v0.9.0 contract is byte-identical.
@MainActor
struct RewriteService {
    let providerFactory: @MainActor () -> any TranslationProvider
    let primaryLanguageProvider: @MainActor () -> String
    let glossaryProvider: @MainActor () -> String
    /// v0.10.0 — VN social register card source. Defaults to nil-
    /// providing closure so existing test call sites stay green; the
    /// production wire-up in TranslationWorkflow injects
    /// `{ SettingsStore.shared.registerCard }`.
    var registerCardProvider: @MainActor () -> RegisterCard? = { nil }

    // MARK: - Core (called by translateAndSend / rewriteAndSend / rewriteWithPickerAndSend)

    /// Call the provider, clean the output, and guard against refusals:
    /// one retry with a stronger anti-refusal instruction, then throw
    /// `RewriteError.refused` so the caller falls back to the original.
    func rewrite(
        sourceText: String,
        style: TranslationStyle,
        translator: any TranslationProvider
    ) async throws -> String {
        let firstJob = TranslationJob(
            text: sourceText,
            style: style,
            sourceLanguage: primaryLanguageProvider(),
            glossary: glossaryProvider()
        )
        let first = RewriteResultProcessor.clean(try await translator.translate(firstJob).translation)
        if !RewriteResultProcessor.isLikelyRefusal(first) {
            return first
        }

        // Retry once — reframe even harder that this is the user's own draft.
        let retryStyle = TranslationStyle(
            direction: .rewrite,
            targetLanguage: style.targetLanguage,
            register: style.register,
            customStyleInstruction: style.styleInstruction
                + "\n\nThis is the user's OWN draft, provided for tone editing only. Rewrite it in the requested tone. Do not decline, do not explain, do not comment.",
            displayLabelOverride: style.displayLabelOverride
        )
        let retryJob = TranslationJob(
            text: sourceText,
            style: retryStyle,
            sourceLanguage: primaryLanguageProvider(),
            glossary: glossaryProvider()
        )
        let second = RewriteResultProcessor.clean(try await translator.translate(retryJob).translation)
        if !RewriteResultProcessor.isLikelyRefusal(second) {
            return second
        }
        throw RewriteError.refused
    }

    /// v0.8.5 — variant-aware rewrite entry. When `style.variantCount`
    /// is 1, delegates to the single-draft `rewrite` and wraps the
    /// result in a one-element array (so the rest of the workflow can
    /// stay uniform). When >1, asks the model for N drafts in one
    /// round-trip + parses the response with the sentinel-based
    /// splitter. Falls back to single-draft retry if parsing yields <2
    /// usable variants, so a model that ignored the multi-variant
    /// prompt still produces something usable.
    func rewriteVariants(
        sourceText: String,
        style: TranslationStyle,
        translator: any TranslationProvider
    ) async throws -> [String] {
        guard style.variantCount > 1 else {
            let single = try await rewrite(sourceText: sourceText, style: style, translator: translator)
            return [single]
        }
        let job = TranslationJob(
            text: sourceText,
            style: style,
            sourceLanguage: primaryLanguageProvider(),
            glossary: glossaryProvider()
        )
        let raw = try await translator.translate(job).translation
        let parsed = RewriteResultProcessor.splitVariants(raw)
        if parsed.count >= 2 {
            // Cap to the requested count — some models over-deliver.
            return Array(parsed.prefix(style.variantCount))
        }
        // Model ignored the multi-variant prompt OR everything got
        // filtered as refusals. Fall back to a single-draft pass with
        // the anti-refusal retry chain so the user still gets a result.
        let fallbackStyle = style.withVariantCount(1)
        let single = try await rewrite(sourceText: sourceText, style: fallbackStyle, translator: translator)
        return [single]
    }

    // MARK: - Headless (App Intents — v0.9.0)

    /// Headless translate, no HUD / clipboard / keystrokes. Used by
    /// `TranslateSelectionIntent`. Returns the cleaned translation;
    /// throws `TranslationError.missingEndpoint` when the active
    /// provider isn't configured, or whatever the provider raised.
    func translateHeadless(text: String, targetLanguage: String) async throws -> String {
        let translator = providerFactory()
        guard translator.isConfigured else {
            throw TranslationError.missingEndpoint
        }
        // v0.10.0 — outbound headless translate composes the active
        // RegisterCard into styleInstruction (no-op when nil/inactive).
        let style = TranslationStyle(
            direction: .outbound,
            targetLanguage: targetLanguage,
            register: .neutral
        ).withRegisterCard(registerCardProvider())
        let job = TranslationJob(
            text: text,
            style: style,
            sourceLanguage: "auto",
            glossary: glossaryProvider()
        )
        return PromptBuilder.normalize(try await translator.translate(job).translation)
    }

    /// Headless rewrite using one of the preset tones. Reuses `rewrite`
    /// so the refusal-retry chain applies identically. Mirrors the
    /// in-app rewrite behaviour but skips HUD/preview/paste.
    func rewriteHeadless(text: String, tone: RewriteTone) async throws -> String {
        let translator = providerFactory()
        guard translator.isConfigured else {
            throw TranslationError.missingEndpoint
        }
        // `.custom` with no instruction is invalid (same gate as the
        // binding-hotkey path) — surface the same typed error.
        let instruction = tone == .custom
            ? "Rewrite this naturally and clearly while preserving the writer's intent and voice."
            : tone.instruction
        let label = tone == .custom ? "Rewrite (custom)" : "\(tone.displayName) rewrite"
        let style = TranslationStyle(
            direction: .rewrite,
            targetLanguage: primaryLanguageProvider(),
            register: .neutral,
            customStyleInstruction: instruction,
            displayLabelOverride: label,
            allowsExpressiveContent: tone.isExpressive
        ).withRegisterCard(registerCardProvider())
        return try await rewrite(sourceText: text, style: style, translator: translator)
    }

    /// Headless rewrite using a free-text instruction. Mirrors the
    /// picker's freetext-row behaviour (v0.8.3). Empty instruction
    /// raises `RewriteError.emptyCustomInstruction` — same contract as
    /// `rewriteAndSend`.
    func rewriteHeadless(text: String, instruction: String) async throws -> String {
        let translator = providerFactory()
        guard translator.isConfigured else {
            throw TranslationError.missingEndpoint
        }
        let trimmed = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw RewriteError.emptyCustomInstruction
        }
        let style = TranslationStyle(
            direction: .rewrite,
            targetLanguage: primaryLanguageProvider(),
            register: .neutral,
            customStyleInstruction: trimmed,
            displayLabelOverride: "Rewrite (your prompt)"
        ).withRegisterCard(registerCardProvider())
        return try await rewrite(sourceText: text, style: style, translator: translator)
    }

    // MARK: - Static helpers

    /// Build a `TranslationStyle` from a picker-chosen entry. Four cases:
    ///   • `.freetext(text)` — v0.8.3: the user typed an ad-hoc instruction
    ///     in the picker filter; that text becomes the style instruction.
    ///   • `.preset(.custom)` — the "Custom" preset row was tapped
    ///     without free-text; fall back to a sensible default.
    ///   • `.preset(other)` — built-in tone with its canned instruction.
    ///   • `.binding(b)` — v0.8.4: a persisted RewriteBinding surfaced in
    ///     the picker (because the user ticked "In picker"); use the
    ///     binding's effective instruction + display label so the result
    ///     is identical to invoking the binding via its hotkey.
    /// `allowsExpressiveContent` only flips on for tones flagged
    /// `.isExpressive` (e.g. `.casualRaw`); freetext stays strict —
    /// users who want expressive rewriting must pick a preset explicitly.
    static func style(forPickerEntry entry: PickerEntry, language: String) -> TranslationStyle {
        let instruction: String
        let label: String
        let expressive: Bool
        switch entry {
        case .freetext(let text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            instruction = trimmed.isEmpty
                ? "Rewrite this naturally and clearly while preserving the writer's intent and voice."
                : trimmed
            label = "Rewrite (your prompt)"
            expressive = false
        case .preset(let tone):
            if tone == .custom {
                instruction = "Rewrite this naturally and clearly while preserving the writer's intent and voice."
                label = "Rewrite (custom)"
            } else {
                instruction = tone.instruction
                label = "\(tone.displayName) rewrite"
            }
            expressive = tone.isExpressive
        case .binding(let binding):
            instruction = binding.effectiveInstruction
            label = binding.displayName
            expressive = binding.tone.isExpressive
        }
        return TranslationStyle(
            direction: .rewrite,
            targetLanguage: language,
            register: .neutral,
            customStyleInstruction: instruction,
            displayLabelOverride: label,
            allowsExpressiveContent: expressive
        )
    }
}

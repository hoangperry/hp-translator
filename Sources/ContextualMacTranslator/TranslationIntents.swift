import AppIntents
import Foundation

// MARK: - Tone mirror

/// `AppEnum` mirror of `RewriteTone` so Shortcuts.app can render a
/// tone-picker in the action UI without the user typing a raw string.
/// Mirror — not the underlying type — because `AppEnum` requires
/// `CaseDisplayRepresentations` metadata that doesn't belong on the
/// production model.
///
/// Expressive tones (`casualRaw`) are NOT listed here in v0.9.0: the
/// Shortcuts UI exposes a single static enum, so adding the Chửi thề
/// case would mean users without the opt-in toggle see it in the picker.
/// Re-enable in v0.9.x once we have an `AppEnum` filter mechanism or a
/// dynamic options provider — for now, users who want expressive
/// rewrites can use `RewriteWithPromptIntent` with a free-text prompt.
enum RewriteToneAppEnum: String, AppEnum, Sendable {
    case polite
    case professional
    case friendly
    case firmButPolite
    case deEscalate
    case concise
    case custom

    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: "Rewrite Tone",
        numericFormat: "\(placeholder: .int) tones"
    )

    static let caseDisplayRepresentations: [RewriteToneAppEnum: DisplayRepresentation] = [
        .polite:        "Polite",
        .professional:  "Professional",
        .friendly:      "Friendly",
        .firmButPolite: "Firm but polite",
        .deEscalate:    "De-escalate",
        .concise:       "Concise",
        .custom:        "Custom (uses default neutral instruction)",
    ]

    /// Map back to the production `RewriteTone`.
    var rewriteTone: RewriteTone {
        switch self {
        case .polite:        return .polite
        case .professional:  return .professional
        case .friendly:      return .friendly
        case .firmButPolite: return .firmButPolite
        case .deEscalate:    return .deEscalate
        case .concise:       return .concise
        case .custom:        return .custom
        }
    }
}

// MARK: - Headless workflow facade

/// Protocol that the App Intents bodies talk to instead of reaching
/// directly into `TranslationWorkflow`. Lets tests inject a mock and
/// keeps the intent file framework-only (no UI dependency).
@MainActor
protocol HeadlessTranslator: AnyObject, Sendable {
    /// Translate `text` into `targetLanguage` (BCP47). Returns the
    /// cleaned translation. Throws if the active provider isn't
    /// configured or the request fails.
    func translateHeadless(text: String, targetLanguage: String) async throws -> String

    /// Rewrite `text` using `tone`. Returns the cleaned rewrite. Throws
    /// on misconfigured provider, refusal-after-retry, or network
    /// failure.
    func rewriteHeadless(text: String, tone: RewriteTone) async throws -> String

    /// Rewrite `text` using a free-text `instruction`. Same error shape
    /// as `rewriteHeadless(text:tone:)`.
    func rewriteHeadless(text: String, instruction: String) async throws -> String
}

// MARK: - Intents

/// Headless intent — no UI side effect. Takes selected text + optional
/// target language and returns the translated string. Shortcuts.app /
/// Spotlight / Siri can chain the result into a further step.
struct TranslateSelectionIntent: AppIntent {
    static let title: LocalizedStringResource = "Translate Text"
    static let description = IntentDescription(
        "Translate text via the active Contextual Mac Translator provider.",
        categoryName: "Translation"
    )

    @Parameter(
        title: "Text",
        description: "The text to translate.",
        inputOptions: String.IntentInputOptions(
            keyboardType: .default,
            capitalizationType: .sentences,
            multiline: true
        )
    )
    var text: String

    @Parameter(
        title: "Target language",
        description: "BCP47 code (e.g. vi, en, ja). Leaves empty to use your default.",
        default: ""
    )
    var targetLanguage: String

    static var parameterSummary: some ParameterSummary {
        Summary("Translate \(\.$text) to \(\.$targetLanguage)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let translator = TranslationIntentRouter.shared.translator
        let target = targetLanguage.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = target.isEmpty ? SettingsStore.shared.primaryLanguage : target
        do {
            let result = try await translator.translateHeadless(text: text, targetLanguage: resolved)
            return .result(value: result)
        } catch {
            throw TranslationIntentError.from(error)
        }
    }
}

/// Headless intent — rewrite `text` using one of the 7 preset tones.
/// The `tone` enum maps 1:1 onto `RewriteTone`. Expressive tones
/// (Chửi thề / `casualRaw`) are intentionally not listed; users who
/// want expressive rewrites should call `RewriteWithPromptIntent`.
struct RewriteWithToneIntent: AppIntent {
    static let title: LocalizedStringResource = "Rewrite with Tone"
    static let description = IntentDescription(
        "Rewrite text in the chosen tone using the active Contextual Mac Translator provider.",
        categoryName: "Rewrite"
    )

    @Parameter(
        title: "Text",
        description: "The text to rewrite.",
        inputOptions: String.IntentInputOptions(
            keyboardType: .default,
            capitalizationType: .sentences,
            multiline: true
        )
    )
    var text: String

    @Parameter(
        title: "Tone",
        description: "Which tone to rewrite the text in.",
        default: .polite
    )
    var tone: RewriteToneAppEnum

    static var parameterSummary: some ParameterSummary {
        Summary("Rewrite \(\.$text) as \(\.$tone)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let translator = TranslationIntentRouter.shared.translator
        do {
            let result = try await translator.rewriteHeadless(text: text, tone: tone.rewriteTone)
            return .result(value: result)
        } catch {
            throw TranslationIntentError.from(error)
        }
    }
}

/// Headless intent — rewrite `text` using a free-text instruction
/// ("make it sound less defensive", "shorter under 2 sentences",
/// "match a 2010s startup-bro voice"). Mirrors the in-app picker's
/// freetext row from v0.8.3.
struct RewriteWithPromptIntent: AppIntent {
    static let title: LocalizedStringResource = "Rewrite with Instruction"
    static let description = IntentDescription(
        "Rewrite text using a custom instruction via the active Contextual Mac Translator provider.",
        categoryName: "Rewrite"
    )

    @Parameter(
        title: "Text",
        description: "The text to rewrite.",
        inputOptions: String.IntentInputOptions(
            keyboardType: .default,
            capitalizationType: .sentences,
            multiline: true
        )
    )
    var text: String

    @Parameter(
        title: "Instruction",
        description: "How to rewrite, e.g. \"warmer reply\" or \"shorter, under 2 sentences\".",
        inputOptions: String.IntentInputOptions(
            keyboardType: .default,
            capitalizationType: .sentences,
            multiline: true
        )
    )
    var instruction: String

    static var parameterSummary: some ParameterSummary {
        Summary("Rewrite \(\.$text) following \(\.$instruction)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let translator = TranslationIntentRouter.shared.translator
        let trimmed = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw TranslationIntentError.emptyInstruction
        }
        do {
            let result = try await translator.rewriteHeadless(text: text, instruction: trimmed)
            return .result(value: result)
        } catch {
            throw TranslationIntentError.from(error)
        }
    }
}

// MARK: - App-shortcuts provider

/// Surfaces the 3 intents to Shortcuts.app, Spotlight, and Siri with
/// human-friendly trigger phrases. Phrases prefix with "Contextual" so
/// they don't collide with Apple Translate's system Siri commands.
struct ContextualTranslatorShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: TranslateSelectionIntent(),
            phrases: [
                "Translate with \(.applicationName)",
                "\(.applicationName) translate",
            ],
            shortTitle: "Translate Text",
            systemImageName: "character.bubble"
        )
        AppShortcut(
            intent: RewriteWithToneIntent(),
            phrases: [
                "Rewrite politely with \(.applicationName)",
                "\(.applicationName) rewrite tone",
            ],
            shortTitle: "Rewrite with Tone",
            systemImageName: "wand.and.sparkles"
        )
        AppShortcut(
            intent: RewriteWithPromptIntent(),
            phrases: [
                "Rewrite with \(.applicationName)",
                "\(.applicationName) custom rewrite",
            ],
            shortTitle: "Rewrite with Instruction",
            systemImageName: "pencil.line"
        )
    }
}

// MARK: - Error mapping

/// Typed errors surfaced into Shortcuts.app. AppIntents will display
/// `localizedDescription` verbatim, so the strings need to read well as
/// user-facing copy, not stack-trace text.
enum TranslationIntentError: LocalizedError {
    case missingProvider
    case providerNotConfigured
    case emptyInstruction
    case refused
    case wrapped(String)

    var errorDescription: String? {
        switch self {
        case .missingProvider:
            return "Rewrite needs an LLM provider (Gemini, Ollama, or an OpenAI-compatible API). Open Contextual Mac Translator's settings to set one up."
        case .providerNotConfigured:
            return "The active provider isn't configured. Open Contextual Mac Translator's settings to add an API key or endpoint."
        case .emptyInstruction:
            return "Please provide an instruction describing how to rewrite the text."
        case .refused:
            return "The model refused this rewrite. Try a different tone, simplify the text, or switch providers."
        case .wrapped(let message):
            return message
        }
    }

    /// Translate the production error types into intent-shaped errors.
    /// Falls back to wrapping the underlying `localizedDescription` so
    /// nothing is lost on unfamiliar errors.
    static func from(_ error: Error) -> TranslationIntentError {
        if let intentError = error as? TranslationIntentError {
            return intentError
        }
        if let rewriteError = error as? RewriteError {
            switch rewriteError {
            case .refused:                  return .refused
            case .emptyCustomInstruction:   return .emptyInstruction
            }
        }
        if let translationError = error as? TranslationError {
            if case .missingEndpoint = translationError {
                return .providerNotConfigured
            }
        }
        return .wrapped(error.localizedDescription)
    }
}

// MARK: - Router

/// AppIntents are constructed by the system, not by our DI graph, so
/// they need a global way to reach the running app's
/// `TranslationWorkflow`. The `AppDelegate` installs the real
/// implementation at launch; tests install a mock.
///
/// `nonisolated(unsafe)` is acceptable here because every write happens
/// once at startup (or in test setUp) and reads happen on `@MainActor`.
@MainActor
final class TranslationIntentRouter {
    static let shared = TranslationIntentRouter()

    /// Pre-launch default: every intent body that calls into this
    /// before `AppDelegate.applicationDidFinishLaunching` runs gets a
    /// clear error instead of a crash.
    private(set) var translator: any HeadlessTranslator = UninstalledHeadlessTranslator()

    func install(_ translator: any HeadlessTranslator) {
        self.translator = translator
    }
}

/// Placeholder implementation that just throws `missingProvider` for
/// every call. Used until the AppDelegate installs the real one.
@MainActor
private final class UninstalledHeadlessTranslator: HeadlessTranslator {
    func translateHeadless(text: String, targetLanguage: String) async throws -> String {
        throw TranslationIntentError.missingProvider
    }
    func rewriteHeadless(text: String, tone: RewriteTone) async throws -> String {
        throw TranslationIntentError.missingProvider
    }
    func rewriteHeadless(text: String, instruction: String) async throws -> String {
        throw TranslationIntentError.missingProvider
    }
}

// MARK: - TranslationWorkflow → HeadlessTranslator adapter

/// Lets the production `TranslationWorkflow` slot into the router
/// without forcing it to know about App Intents directly. AppDelegate
/// installs it at launch via `TranslationIntentRouter.shared.install`.
extension TranslationWorkflow: HeadlessTranslator {
    func translateHeadless(text: String, targetLanguage: String) async throws -> String {
        try await performTranslationHeadless(text: text, targetLanguage: targetLanguage)
    }
    func rewriteHeadless(text: String, tone: RewriteTone) async throws -> String {
        try await performRewriteHeadless(text: text, tone: tone)
    }
    func rewriteHeadless(text: String, instruction: String) async throws -> String {
        try await performRewriteHeadless(text: text, instruction: instruction)
    }
}

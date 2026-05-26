import Foundation

/// v0.11.0 — Prompt Engineer mode. One binding = (hotkey + target
/// language + style instruction for prompt expansion). The user types a
/// minimal Vietnamese keyword sketch of a coding task, presses the
/// bound hotkey, and the workflow captures the line + sends it through
/// the translate provider with `direction = .expand`. The provider
/// (currently the Supabase Edge Function via BackendProvider) routes
/// the request to `EXPAND_SYSTEM_PROMPT` and returns a complete
/// English prompt ready to paste into Claude Code, Codex, ChatGPT, or
/// Claude Desktop.
///
/// Deliberately separate from `RewriteBinding`: a rewrite is same-
/// language tone-adjust; an expansion is cross-language and produces
/// substantially longer output than the input. The two flows want
/// different prompts, temperatures, and UI affordances.
struct PromptBinding: Codable, Equatable, Identifiable, Hashable, Sendable {
    var id: UUID
    /// User-visible label shown in Settings rows + the HUD on dispatch.
    /// Defaults to "Prompt expand" but free-text — users can name it
    /// "Claude Code prompt", "Codex bug fix", etc.
    var name: String
    var hotkey: HotkeyConfig
    /// BCP47 target language for the expanded prompt. Almost always
    /// "en" because AI coding assistants speak English best, but kept
    /// configurable for users who want JP / ZH expansions.
    var targetLanguage: String
    /// The expansion guidelines sent to the LLM as the style
    /// instruction. Defaults to `PromptExpansion.defaultStyleInstruction`
    /// when blank — that template covers the common "Claude Code +
    /// Codex + ChatGPT" use case described in the Path A recipe page.
    /// Users override here if they want a different shape (per-AI
    /// variant, specific tech stack context, alternative output format).
    var styleInstruction: String

    init(
        id: UUID = UUID(),
        name: String = "Prompt expand",
        hotkey: HotkeyConfig,
        targetLanguage: String = "en",
        styleInstruction: String = ""
    ) {
        self.id = id
        self.name = name
        self.hotkey = hotkey
        self.targetLanguage = targetLanguage
        self.styleInstruction = styleInstruction
    }

    /// The style instruction actually sent to the LLM. Falls back to
    /// the default template when the user has not customised the
    /// instruction — keeps the binding usable out of the box.
    var effectiveStyleInstruction: String {
        let trimmed = styleInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? PromptExpansion.defaultStyleInstruction : trimmed
    }

    /// Compose a `TranslationStyle` for the workflow. Direction is
    /// hard-pinned to `.expand` so the BackendProvider emits
    /// `direction: "expand"` on the wire and the SaaS Supabase Edge
    /// Function routes to EXPAND_SYSTEM_PROMPT. Register stays
    /// `.neutral` — Prompt Engineer mode is cross-language synthesis,
    /// not register-sensitive.
    func style() -> TranslationStyle {
        TranslationStyle(
            direction: .expand,
            targetLanguage: targetLanguage,
            register: .neutral,
            customStyleInstruction: effectiveStyleInstruction,
            displayLabelOverride: name
        )
    }
}

/// v0.11.0 — Shared constants for Prompt Engineer mode. Kept at file
/// scope so the Settings UI default placeholder text and the runtime
/// binding fallback share a single source of truth.
enum PromptExpansion {
    /// Default expansion instructions used when a `PromptBinding`
    /// leaves `styleInstruction` blank. Mirrors the meta-prompt
    /// documented on the marketing recipe page at
    /// `/recipes/prompt-expander` so users who copy from there land on
    /// the same defaults.
    static let defaultStyleInstruction = """
You are a prompt engineer for AI coding assistants (Claude Code, Codex, ChatGPT, Claude Desktop).

The input is a minimal Vietnamese keyword sketch of a coding task. Expand it into a complete prompt in the target language that:

- Restates the task explicitly in one sentence at the top
- Lays out a numbered plan of what the assistant should do
- Asks for code + tests + a brief explanation of trade-offs
- Notes reasonable assumptions about the tech stack if the keywords omit it
- Requests clarifying questions only if essential context is genuinely ambiguous
- Preserves any concrete technical details from the input verbatim (file names, function names, version numbers, error strings)

Output ONLY the final prompt. No commentary, no preamble, no markdown fences around the whole output.
"""
}

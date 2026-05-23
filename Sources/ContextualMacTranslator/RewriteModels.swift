import Carbon.HIToolbox
import Foundation

/// Target tone for the contextual-rewrite feature. The rewrite keeps the
/// input language and only changes delivery — politeness transfer,
/// de-escalation, register shift. See `RewriteBinding`.
enum RewriteTone: String, Codable, CaseIterable, Identifiable, Sendable {
    case polite
    case professional
    case friendly
    case firmButPolite
    case deEscalate
    case concise
    case custom

    var id: String { rawValue }

    /// Label shown in Settings + the HUD.
    var displayName: String {
        switch self {
        case .polite:        return "Polite"
        case .professional:  return "Professional"
        case .friendly:      return "Friendly"
        case .firmButPolite: return "Firm but polite"
        case .deEscalate:    return "De-escalate"
        case .concise:       return "Concise"
        case .custom:        return "Custom"
        }
    }

    /// LLM instruction describing the target tone. For `.custom` this is
    /// empty — the binding's free-text `customInstruction` is used instead.
    var instruction: String {
        switch self {
        case .polite:
            return "Rewrite the message politely and warmly. Keep it respectful and easy to read; soften any harsh or blunt wording while keeping the point clear."
        case .professional:
            return "Rewrite the message in clear, competent, professional language. Remove slang and raw emotion; stay confident, neutral, and businesslike."
        case .friendly:
            return "Rewrite the message in a warm, approachable, friendly tone — like talking to a familiar person. Keep it light and natural, not stiff."
        case .firmButPolite:
            return "Rewrite the message so it stays direct and clear about what is needed, while remaining courteous and non-aggressive. Do not water down the actual request."
        case .deEscalate:
            return "Rewrite the message to lower tension. Acknowledge the other person's frustration, take responsibility where appropriate, and stay calm and sincere — never defensive or accusatory."
        case .concise:
            return "Rewrite the message as short and direct as possible without losing any fact, number, or request. Cut filler; keep one clear point."
        case .custom:
            return ""
        }
    }
}

/// One rewrite binding = (target tone + optional custom instruction +
/// hotkey). Users can have N of these; each registers a global hotkey
/// that rewrites the current input line in the chosen tone.
///
/// Deliberately separate from `OutboundBinding`: a rewrite has no target
/// language and no formal/casual `Register` — it has a tone. Reusing
/// `OutboundBinding` would leave those fields meaningless.
struct RewriteBinding: Codable, Equatable, Identifiable, Hashable, Sendable {
    var id: UUID
    var tone: RewriteTone
    /// Free-text instruction. Required when `tone == .custom`; for the
    /// preset tones it acts as an optional override of the preset.
    var customInstruction: String
    var hotkey: HotkeyConfig

    init(
        id: UUID = UUID(),
        tone: RewriteTone,
        customInstruction: String = "",
        hotkey: HotkeyConfig
    ) {
        self.id = id
        self.tone = tone
        self.customInstruction = customInstruction
        self.hotkey = hotkey
    }

    /// Label for Settings rows + the HUD.
    var displayName: String {
        tone == .custom ? "Custom rewrite" : "\(tone.displayName) rewrite"
    }

    /// The tone instruction actually sent to the LLM. For `.custom` it is
    /// the free text; for a preset, the free text overrides the preset
    /// when non-empty, otherwise the preset's built-in instruction.
    var effectiveInstruction: String {
        let custom = customInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
        if tone == .custom {
            return custom
        }
        return custom.isEmpty ? tone.instruction : custom
    }

    /// Build the `TranslationStyle` for a rewrite job. `language` is the
    /// user's primary language — only a hint; the rewrite prompt pins the
    /// output to the *input's* language regardless.
    func style(language: String) -> TranslationStyle {
        TranslationStyle(
            direction: .rewrite,
            targetLanguage: language,
            register: .neutral,
            customStyleInstruction: effectiveInstruction,
            displayLabelOverride: displayName
        )
    }

    /// Default seed binding — a single "Polite" rewrite on ⌥R. Not added
    /// automatically (rewrite needs an LLM provider the user may not have
    /// configured); offered by the Settings "Add" button.
    static let defaultPolite = RewriteBinding(
        tone: .polite,
        hotkey: HotkeyConfig(keyCode: kVK_ANSI_R, modifiers: Int(optionKey))
    )
}

/// Errors specific to the contextual-rewrite flow.
enum RewriteError: LocalizedError {
    /// The model declined to rewrite the message (returned a refusal /
    /// moralizing response) even after one retry with a stronger prompt.
    case refused
    /// A `.custom` rewrite binding has no instruction set. The user added
    /// the binding but never typed what tone they wanted.
    case emptyCustomInstruction

    var errorDescription: String? {
        switch self {
        case .refused:
            return "Couldn't rewrite this message — the model declined. Your original text was kept."
        case .emptyCustomInstruction:
            return "This rewrite binding uses a custom tone but has no instruction. Open Settings → Contextual rewrite and describe the tone you want."
        }
    }
}

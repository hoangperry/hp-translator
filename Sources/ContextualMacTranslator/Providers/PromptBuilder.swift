import Foundation

/// System + user prompt construction shared by direct-API providers.
///
/// Mirrors `translator-server/server.py` (`SYSTEM_PROMPT`, `PERSONA_RULES`,
/// `build_user_prompt`, `temperature_for`, `normalize_translation`) so a
/// translation request executed directly by the app produces the same text
/// quality as the same request proxied through the backend.
enum PromptBuilder {
    static let systemPrompt = """
    You are a context-aware chat translator.
    Translate meaning, not word-for-word.
    Keep names, code identifiers, URLs, and product names unchanged unless the glossary says otherwise.
    Apply glossary mappings exactly.
    Return only the translated text. Do not add explanations, quotes, markdown, or labels.
    """

    /// Style instruction derived from the (target language, register) pair
    /// on `style`. Replaces the v0.2 hardcoded persona switch — works for
    /// arbitrary BCP47 target languages.
    static func styleRule(for style: TranslationStyle) -> String {
        style.styleInstruction
    }

    /// User prompt body. The LLM receives `systemPrompt` separately (or
    /// concatenated for providers that don't support a system role).
    static func userPrompt(for job: TranslationJob) -> String {
        let glossary = job.glossary.isEmpty ? "(empty)" : job.glossary
        let style = job.style.styleInstruction
        return """
        Task: translate chat text.
        Direction: \(job.direction.rawValue)
        Source language: \(job.sourceLanguage)
        Target language: \(job.targetLanguage) (\(LanguageCatalog.englishName(for: job.targetLanguage)))
        Register: \(job.register.rawValue)
        Style rule: \(style)
        Glossary:
        \(glossary)

        Text:
        \(job.text)

        Return only the translation.
        """
    }

    /// Sampling temperature. Casual chat tolerates a touch more variation;
    /// formal + neutral stay near-deterministic.
    static func temperature(for style: TranslationStyle) -> Double {
        switch style.register {
        case .casual: return 0.35
        case .formal, .neutral: return 0.2
        }
    }

    /// Strip trailing whitespace + matching outer quotes some LLMs add even
    /// when told not to. Mirrors Python `normalize_translation`.
    static func normalize(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            return trimmed
        }
        let first = trimmed.first!
        let last = trimmed.last!
        if first == last && (first == "\"" || first == "'") {
            return String(trimmed.dropFirst().dropLast())
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }
}

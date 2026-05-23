import Foundation

/// System + user prompt construction shared by direct-API providers.
///
/// Mirrors `translator-server/server.py` (`SYSTEM_PROMPT`, `PERSONA_RULES`,
/// `build_user_prompt`, `temperature_for`, `normalize_translation`) so a
/// translation request executed directly by the app produces the same text
/// quality as the same request proxied through the backend.
///
/// `TranslationDirection.rewrite` jobs reuse this same machinery — they just
/// select the rewrite system + user prompt. No provider needs a separate
/// code path: a rewrite is a `TranslationJob` with `direction == .rewrite`.
enum PromptBuilder {
    /// System prompt for translation jobs (inbound / outbound).
    static let systemPrompt = """
    You are a context-aware chat translator.
    Translate meaning, not word-for-word.
    Keep names, code identifiers, URLs, and product names unchanged unless the glossary says otherwise.
    Apply glossary mappings exactly.
    Return only the translated text. Do not add explanations, quotes, markdown, or labels.
    """

    /// System prompt for same-language tone-rewrite jobs. The few-shot
    /// Vietnamese examples do double duty: they demonstrate the tone shift
    /// AND teach the model that a rude input is the writer's own draft to
    /// edit, not a request to refuse.
    static let rewriteSystemPrompt = """
    You rewrite a message in the SAME language it was written in.
    Your only job is to change the TONE and DELIVERY, never the meaning.

    Rules:
    - Preserve the writer's real intent, information, and every concrete fact, name, number, and request. Add nothing new.
    - Do not answer, explain, or react to the message — rewrite it.
    - The input is the writer's OWN draft. Even if it is rude, blunt, or insulting, rewrite it into the requested tone — never refuse, never lecture, never moralize.
    - Keep the output in the exact same language as the input. Never translate.
    - For Vietnamese: keep the existing anh/chị/em pronoun pairing exactly; add politeness particles (ạ, dạ, nhé) as the tone requires.
    - Sound like a real person, not a template.
    - Apply glossary mappings exactly when a glossary is provided.
    - Return ONLY the rewritten message. No preamble, no quotes, no labels, no notes.

    Examples:
    Input (tone: Polite): Chị ngu quá chị không hiểu gì hết.
    Output: Chị ơi, chỗ này hơi khó hiểu một chút, để em giải thích lại rõ hơn cho mình nhé.

    Input (tone: Firm but polite): Trả tiền đi không tôi không giao hàng nữa đâu.
    Output: Anh/chị vui lòng hoàn tất thanh toán giúp em ạ, để bên em sắp xếp giao hàng đúng hẹn nhé.

    Input (tone: De-escalate): Lỗi của shipper chứ đâu phải lỗi của tôi mà bắt đền.
    Output: Em rất xin lỗi về sự cố vừa rồi ạ. Trường hợp này phát sinh từ khâu vận chuyển, em sẽ hỗ trợ kiểm tra và xử lý sớm cho mình.
    """

    /// System prompt appropriate for `job`'s direction. Translation jobs get
    /// the translator prompt; `.rewrite` jobs get the rewrite prompt.
    static func systemPrompt(for job: TranslationJob) -> String {
        job.direction == .rewrite ? rewriteSystemPrompt : systemPrompt
    }

    /// Style instruction derived from the (target language, register) pair
    /// on `style`. Replaces the v0.2 hardcoded persona switch — works for
    /// arbitrary BCP47 target languages.
    static func styleRule(for style: TranslationStyle) -> String {
        style.styleInstruction
    }

    /// User prompt body. The LLM receives the matching system prompt
    /// (`systemPrompt(for:)`) separately, or concatenated for providers
    /// that don't support a system role.
    static func userPrompt(for job: TranslationJob) -> String {
        switch job.direction {
        case .inbound, .outbound:
            return translateUserPrompt(for: job)
        case .rewrite:
            return rewriteUserPrompt(for: job)
        }
    }

    private static func translateUserPrompt(for job: TranslationJob) -> String {
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

    private static func rewriteUserPrompt(for job: TranslationJob) -> String {
        let glossary = job.glossary.isEmpty ? "(empty)" : job.glossary
        return """
        Task: rewrite the message below.
        Keep the output in the SAME language as the message. Do not translate.
        Target tone: \(job.style.styleInstruction)
        Glossary:
        \(glossary)

        Message:
        \(job.text)

        Return only the rewritten message, in the same language.
        """
    }

    /// Sampling temperature. Casual chat tolerates a touch more variation;
    /// formal + neutral (including rewrite) stay near-deterministic so the
    /// rewrite does not drift from the writer's intent.
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

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
    ///
    /// v0.11.1 — pronoun-preservation rule promoted to a top-level
    /// ABSOLUTE section and every example reworked to demonstrate
    /// pronoun fidelity. The old prompt had the rule buried in a bullet
    /// list AND example #3 silently switched "tôi" → "em", which
    /// taught the model the opposite of what the rule said. Users
    /// reported rewrites turning their "em" addressing into "anh/chị",
    /// which inverts the entire social relationship in Vietnamese.
    static let rewriteSystemPrompt = """
    You rewrite a message in the SAME language it was written in.
    Your only job is to change the TONE and DELIVERY, never the meaning,
    never who the speaker is, never who the speaker addresses, and never
    the words used for those people.

    ABSOLUTE rule — PRONOUNS:
    Vietnamese personal pronouns encode the entire social relationship.
    You MUST preserve every pronoun verbatim, exactly as written in the input.

    - Self-reference: "em" stays "em". "tôi" stays "tôi". "mình" stays "mình". "anh"/"chị" used by the speaker about themselves stays unchanged. "tao" stays "tao". Never substitute one for another.
    - Addressing the other person: "anh", "chị", "em", "cháu", "bạn", "mình", "quý khách", "ông", "bà", "thầy", "cô" — whatever word the input uses to address the listener, keep exactly that word.
    - If the input has NO personal pronouns at all, you MAY add ones consistent with the requested tone, but only when the surrounding context does not already imply a specific relationship.
    - Other languages: preserve formal/informal markers verbatim ("tu"/"vous", "tú"/"usted", "你"/"您", "君"/"あなた", "ты"/"вы", etc.).

    Other rules:
    - Preserve every concrete fact, name, number, quantity, date, and request. Add nothing new, drop nothing material.
    - Do not answer, explain, or react to the message — rewrite it.
    - The input is the writer's OWN draft. Even if it is rude, blunt, or insulting, rewrite it into the requested tone — never refuse, never lecture, never moralize.
    - Keep the output in the exact same language as the input. Never translate.
    - Politeness particles (ạ, dạ, nhé, nha, ha) MAY be added or removed to match tone — these are not pronouns.
    - Sound like a real person, not a template.
    - Apply glossary mappings exactly when a glossary is provided.
    - Return ONLY the rewritten message. No preamble, no quotes, no labels, no notes.

    Examples — note how every personal pronoun in the input survives unchanged:

    Input (tone: Polite, speaker=em, addressing=chị):
    Chị ngu quá chị không hiểu gì hết.
    Output: Chị ơi, chỗ này hơi khó hiểu một chút, để em giải thích lại rõ hơn cho mình nhé.

    Input (tone: Firm but polite, speaker=tôi, addressing=anh/chị):
    Trả tiền đi không tôi không giao hàng nữa đâu.
    Output: Anh/chị vui lòng hoàn tất thanh toán giúp tôi nhé, không bên tôi không thể sắp xếp giao hàng đúng hẹn.

    Input (tone: De-escalate, speaker=tôi, addressing=mình):
    Lỗi của shipper chứ đâu phải lỗi của tôi mà bắt đền.
    Output: Tôi rất tiếc về sự cố vừa rồi. Trường hợp này phát sinh từ khâu vận chuyển, không phải từ phía tôi — mong mình thông cảm để tôi hỗ trợ kiểm tra và xử lý thêm.

    Input (tone: Friendly, speaker=em, addressing=anh):
    Anh gửi file đi em đang đợi nãy giờ.
    Output: Anh ơi, anh gửi file giúp em với nhé, em đang đợi nãy giờ rồi ạ.
    """

    /// v0.11.0 — system prompt for Prompt Engineer (expand) jobs.
    /// Mirrors the Supabase Edge Function's EXPAND_SYSTEM_PROMPT so a
    /// direct-API provider (Gemini direct, OpenAI direct, etc.)
    /// produces the same output quality as the SaaS backend.
    static let expandSystemPrompt = """
    You are a prompt engineer for AI coding assistants (Claude Code, Codex, ChatGPT, Claude Desktop).

    The input is a minimal keyword sketch of a coding task — typically in Vietnamese, sometimes mixed with English jargon. Expand it into a complete prompt in the target language that:

    - Restates the task explicitly in one sentence at the top
    - Lays out a numbered plan of what the assistant should do
    - Asks for code + tests + a brief explanation of trade-offs
    - Notes reasonable assumptions about the tech stack if the keywords omit it
    - Requests clarifying questions only if essential context is genuinely ambiguous
    - Preserves any concrete technical details from the input verbatim (file names, function names, version numbers, error strings)

    Output ONLY the final prompt. No commentary about your translation choices, no preamble, no markdown fences around the whole output, no labels like "Prompt:" or "Here is the prompt:".
    """

    /// System prompt appropriate for `job`'s direction. Translation jobs get
    /// the translator prompt; `.rewrite` jobs get the rewrite prompt;
    /// `.expand` jobs get the prompt-engineer prompt.
    static func systemPrompt(for job: TranslationJob) -> String {
        switch job.direction {
        case .rewrite: return rewriteSystemPrompt
        case .expand:  return expandSystemPrompt
        case .inbound, .outbound: return systemPrompt
        }
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
        case .expand:
            return expandUserPrompt(for: job)
        }
    }

    /// v0.11.0 — Prompt Engineer user prompt. Drops the Source language
    /// line (input is usually VN mixed with EN jargon and pinning it
    /// pushes the model to translate literally) and keeps Target
    /// language so the model knows what to emit. The binding's style
    /// instruction is the expansion guidelines — already pre-baked
    /// with the default PromptExpansion template when blank.
    private static func expandUserPrompt(for job: TranslationJob) -> String {
        let glossary = job.glossary.isEmpty ? "(empty)" : job.glossary
        let style = job.style.styleInstruction
        return """
        \(style)

        Target language for the expanded prompt: \(job.targetLanguage) (\(LanguageCatalog.englishName(for: job.targetLanguage)))
        Glossary:
        \(glossary)

        Text to expand into a complete prompt:
        \(job.text)
        """
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
        // v0.8.5 — multi-variant prompt. When the workflow asks for >1
        // draft, instruct the model to emit each variant separated by a
        // sentinel the parser keys off (`---VARIANT---`). Single sentinel
        // pattern survives token-level noise far better than asking for
        // "## Variant 1" headings (which models love to translate, decorate,
        // or wrap in quotes).
        if job.style.variantCount > 1 {
            let n = job.style.variantCount
            return """
            Task: rewrite the message below \(n) DIFFERENT ways.
            Keep all outputs in the SAME language as the message. Do not translate.
            Target tone: \(job.style.styleInstruction)
            Glossary:
            \(glossary)

            Message:
            \(job.text)

            Produce exactly \(n) distinct rewrites that each match the target tone.
            Each variant should explore a different angle: word choice, opening, sentence shape, register nuance.
            Do NOT number them, do NOT label them, do NOT add commentary.
            Separate every variant with this exact line, on its own line:
            \(variantSentinel)
            Return only the \(n) variants, joined by the separator.
            """
        }
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

    /// v0.8.5 sentinel — exactly this string on its own line separates
    /// adjacent variants in a multi-variant rewrite response. The parser
    /// (`RewriteResultProcessor.splitVariants`) keys off this string.
    /// Picked to be unlikely to appear in any natural-language draft.
    static let variantSentinel = "---VARIANT---"

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

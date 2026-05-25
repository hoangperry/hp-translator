import Testing

@testable import ContextualMacTranslator

@Suite("PromptBuilder")
struct PromptBuilderTests {
    @Test("System prompt matches the backend constant")
    func systemPromptStable() {
        let prompt = PromptBuilder.systemPrompt
        #expect(prompt.contains("context-aware chat translator"))
        #expect(prompt.contains("Return only the translated text"))
        // No accidental trailing whitespace / newline noise that would
        // break LLMs that hash prompts for caching.
        #expect(!prompt.hasSuffix("\n"))
        #expect(!prompt.hasSuffix(" "))
    }

    @Test("Style rule covers all three legacy personas + arbitrary lang")
    func styleRulesCoverPersonas() {
        let presets: [Persona] = [.vietnameseReader, .japaneseBusiness, .japaneseCasual]
        for persona in presets {
            #expect(!PromptBuilder.styleRule(for: persona).isEmpty)
        }
        // New languages get a non-empty style rule too.
        let korean = TranslationStyle(direction: .outbound, targetLanguage: "ko", register: .formal)
        #expect(!PromptBuilder.styleRule(for: korean).isEmpty)
    }

    @Test("User prompt embeds task fields verbatim")
    func userPromptEmbedsFields() {
        let job = TranslationJob(text: "Xin chao anh", style: .japaneseBusiness, sourceLanguage: "vi", glossary: "API = エーピーアイ"
        )

        let prompt = PromptBuilder.userPrompt(for: job)

        #expect(prompt.contains("Direction: outbound"))
        #expect(prompt.contains("Source language: vi"))
        #expect(prompt.contains("Target language: ja"))
        #expect(prompt.contains("Register: formal"))
        #expect(prompt.contains("API = エーピーアイ"))
        #expect(prompt.contains("Xin chao anh"))
        #expect(prompt.hasSuffix("Return only the translation."))
    }

    @Test("v0.10.0 — TranslationStyle.styleInstruction prepends RegisterCard [Register] block when active")
    func registerCardComposesIntoStyle() {
        // Outbound translate style with a Bắc/chị/formal register card.
        // styleInstruction should include the composed block; the user
        // prompt body composes via PromptBuilder.styleRule which reads
        // styleInstruction.
        let card = RegisterCard(dialect: .northern, kinship: .chi, formality: .formal)
        let style = TranslationStyle(
            direction: .outbound,
            targetLanguage: "vi",
            register: .formal,
            customStyleInstruction: "Be polite."
        ).withRegisterCard(card)
        let job = TranslationJob(
            text: "hi",
            style: style,
            sourceLanguage: "en",
            glossary: ""
        )
        let prompt = PromptBuilder.userPrompt(for: job)
        #expect(prompt.contains("[Register]"))
        #expect(prompt.contains("Northern (Bắc) dialect"))
        #expect(prompt.contains("addresses the listener as \"chị\""))
        #expect(prompt.contains("formality: formal"))
        #expect(prompt.contains("[Tone]"))
        #expect(prompt.contains("Be polite."))
    }

    @Test("v0.10.0 — Inactive RegisterCard is a no-op (v0.9.x prompt byte-identical)")
    func inactiveRegisterCardNoOp() {
        // Default-init card is all-unspecified + empty roleHint = inactive.
        let style = TranslationStyle(
            direction: .rewrite,
            targetLanguage: "vi",
            register: .neutral,
            customStyleInstruction: "Be polite."
        ).withRegisterCard(RegisterCard())
        let job = TranslationJob(
            text: "hi",
            style: style,
            sourceLanguage: "vi",
            glossary: ""
        )
        let prompt = PromptBuilder.userPrompt(for: job)
        #expect(!prompt.contains("[Register]"))
        #expect(!prompt.contains("[Tone]"))
        // The original instruction still flows through unchanged.
        #expect(prompt.contains("Be polite."))
    }

    @Test("v0.10.0 — nil RegisterCard is a no-op (existing TranslationStyle calls unchanged)")
    func nilRegisterCardNoOp() {
        let style = TranslationStyle(
            direction: .rewrite,
            targetLanguage: "vi",
            register: .neutral,
            customStyleInstruction: "Be polite."
        )
        #expect(style.registerCard == nil)
        #expect(style.styleInstruction == "Be polite.")
    }

    @Test("Empty glossary renders as `(empty)`")
    func emptyGlossaryFallback() {
        let job = TranslationJob(text: "hi", style: .vietnameseReader, sourceLanguage: "ja", glossary: ""
        )

        #expect(PromptBuilder.userPrompt(for: job).contains("Glossary:\n(empty)"))
    }

    @Test("Casual persona uses higher temperature")
    func temperatureForCasual() {
        #expect(PromptBuilder.temperature(for: .japaneseCasual) > PromptBuilder.temperature(for: .japaneseBusiness))
        #expect(PromptBuilder.temperature(for: .japaneseBusiness) == PromptBuilder.temperature(for: .vietnameseReader))
    }

    @Test("Normalization strips outer matching quotes + whitespace")
    func normalizationStripsQuotes() {
        #expect(PromptBuilder.normalize(" \"hello\" ") == "hello")
        #expect(PromptBuilder.normalize("'hi'") == "hi")
        // Non-matching outer chars are kept.
        #expect(PromptBuilder.normalize("\"hi") == "\"hi")
        #expect(PromptBuilder.normalize("hi\"") == "hi\"")
    }

    @Test("Normalization preserves text without outer quotes")
    func normalizationKeepsPlain() {
        #expect(PromptBuilder.normalize("ありがとう") == "ありがとう")
    }

    @Test("Normalization survives single-character input")
    func normalizationShortInput() {
        #expect(PromptBuilder.normalize("a") == "a")
        #expect(PromptBuilder.normalize("") == "")
    }
}

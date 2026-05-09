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

    @Test("Persona style rules cover all three personas")
    func styleRulesCoverPersonas() {
        for persona in Persona.allCases {
            let rule = PromptBuilder.styleRule(for: persona)
            #expect(!rule.isEmpty, "Persona \(persona.rawValue) missing style rule")
        }
    }

    @Test("User prompt embeds task fields verbatim")
    func userPromptEmbedsFields() {
        let job = TranslationJob(
            text: "Xin chao anh",
            direction: .outbound,
            sourceLanguage: "vi",
            targetLanguage: "ja",
            persona: .japaneseBusiness,
            glossary: "API = エーピーアイ"
        )

        let prompt = PromptBuilder.userPrompt(for: job)

        #expect(prompt.contains("Direction: outbound"))
        #expect(prompt.contains("Source language: vi"))
        #expect(prompt.contains("Target language: ja"))
        #expect(prompt.contains("Persona: japaneseBusiness"))
        #expect(prompt.contains("API = エーピーアイ"))
        #expect(prompt.contains("Xin chao anh"))
        #expect(prompt.hasSuffix("Return only the translation."))
    }

    @Test("Empty glossary renders as `(empty)`")
    func emptyGlossaryFallback() {
        let job = TranslationJob(
            text: "hi",
            direction: .inbound,
            sourceLanguage: "ja",
            targetLanguage: "vi",
            persona: .vietnameseReader,
            glossary: ""
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

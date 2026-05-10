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

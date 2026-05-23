import Foundation
import Testing

@testable import ContextualMacTranslator

@Suite("Rewrite models")
struct RewriteModelsTests {
    @Test("Every tone has a non-empty display name")
    func toneDisplayNames() {
        for tone in RewriteTone.allCases {
            #expect(!tone.displayName.isEmpty)
        }
    }

    @Test("Preset tones carry an instruction; custom does not")
    func toneInstructions() {
        for tone in RewriteTone.allCases where tone != .custom {
            #expect(!tone.instruction.isEmpty)
        }
        #expect(RewriteTone.custom.instruction.isEmpty)
    }

    @Test("Preset binding without override uses the preset instruction")
    func effectiveInstructionPreset() {
        let binding = RewriteBinding(tone: .polite, hotkey: .defaultInbound)
        #expect(binding.effectiveInstruction == RewriteTone.polite.instruction)
    }

    @Test("Preset binding with free-text uses the override")
    func effectiveInstructionPresetOverride() {
        let binding = RewriteBinding(
            tone: .professional,
            customInstruction: "Make it sound like a senior manager",
            hotkey: .defaultInbound
        )
        #expect(binding.effectiveInstruction == "Make it sound like a senior manager")
    }

    @Test("Custom tone always uses the free-text instruction")
    func effectiveInstructionCustom() {
        let binding = RewriteBinding(
            tone: .custom,
            customInstruction: "Rewrite as a warm reply to an angry client, under 2 sentences",
            hotkey: .defaultInbound
        )
        #expect(binding.effectiveInstruction == "Rewrite as a warm reply to an angry client, under 2 sentences")
    }

    @Test("style() produces a rewrite-direction TranslationStyle")
    func styleProducesRewriteDirection() {
        let binding = RewriteBinding(tone: .deEscalate, hotkey: .defaultInbound)
        let style = binding.style(language: "vi")

        #expect(style.direction == .rewrite)
        #expect(style.targetLanguage == "vi")
        #expect(style.register == .neutral)
        #expect(style.customStyleInstruction == RewriteTone.deEscalate.instruction)
        #expect(style.displayLabelOverride == binding.displayName)
        #expect(style.displayName == "De-escalate rewrite")
        #expect(style.displayBadge == "✎")
    }

    @Test("RewriteBinding survives a Codable round-trip")
    func codableRoundTrip() throws {
        let original = RewriteBinding(
            tone: .firmButPolite,
            customInstruction: "keep it short",
            hotkey: .defaultOutboundFormal
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RewriteBinding.self, from: data)
        #expect(decoded == original)
    }

    @Test("Only LLM providers support rewrite")
    func supportsRewrite() {
        let llm: [DirectProviderKind] = [.gemini, .ollama, .openAICompatible, .geminiCLI, .codexCLI, .mock]
        let mtOnly: [DirectProviderKind] = [.deepl, .libreTranslate, .googleTranslate]
        for kind in llm {
            #expect(kind.supportsRewrite == true)
        }
        for kind in mtOnly {
            #expect(kind.supportsRewrite == false)
        }
    }
}

@Suite("Rewrite settings")
@MainActor
struct RewriteSettingsTests {
    private func makeDefaults(_ name: String = UUID().uuidString) -> UserDefaults {
        let suiteName = "app.lookerlab.translator.rewrite-tests.\(name)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func makeKeychain() -> KeychainCredentialStore {
        KeychainCredentialStore(service: "app.lookerlab.translator.rewrite-tests.\(UUID().uuidString)")
    }

    @Test("rewriteBindings defaults to empty")
    func rewriteBindingsEmptyByDefault() {
        let store = SettingsStore(defaults: makeDefaults(), keychain: makeKeychain())
        #expect(store.rewriteBindings.isEmpty)
    }

    @Test("rewriteBindings persist across reload")
    func rewriteBindingsPersist() {
        let defaults = makeDefaults("rewrite-persist")
        let keychain = makeKeychain()
        let store = SettingsStore(defaults: defaults, keychain: keychain)

        store.rewriteBindings = [RewriteBinding(tone: .polite, hotkey: .defaultInbound)]

        let reloaded = SettingsStore(defaults: defaults, keychain: keychain)
        #expect(reloaded.rewriteBindings.count == 1)
        #expect(reloaded.rewriteBindings.first?.tone == .polite)
    }

    @Test("rewriteAvailable is true for direct LLM providers, false otherwise")
    func rewriteAvailability() {
        let store = SettingsStore(defaults: makeDefaults("rewrite-avail"), keychain: makeKeychain())

        store.translationSource = .directAPI
        store.directProvider = .gemini
        #expect(store.rewriteAvailable == true)

        store.directProvider = .deepl
        #expect(store.rewriteAvailable == false)

        store.translationSource = .customBackend
        store.directProvider = .gemini
        #expect(store.rewriteAvailable == false)
    }

    @Test("bindingLabel detects a hotkey used by a rewrite binding")
    func bindingLabelDetectsRewriteHotkey() {
        let store = SettingsStore(defaults: makeDefaults("rewrite-conflict"), keychain: makeKeychain())
        let hotkey = HotkeyConfig(keyCode: 15, modifiers: 2048)
        store.rewriteBindings = [RewriteBinding(tone: .friendly, hotkey: hotkey)]

        #expect(store.bindingLabel(usingHotkey: hotkey) == "Friendly rewrite")
    }

    @Test("pickerHotkey defaults to nil and persists when set")
    func pickerHotkeyDefaultAndPersist() {
        let defaults = makeDefaults("picker-hotkey")
        let keychain = makeKeychain()
        let store = SettingsStore(defaults: defaults, keychain: keychain)
        #expect(store.pickerHotkey == nil)

        let hotkey = HotkeyConfig(keyCode: 36, modifiers: 2304)  // ⌘⌥⏎
        store.pickerHotkey = hotkey

        let reloaded = SettingsStore(defaults: defaults, keychain: keychain)
        #expect(reloaded.pickerHotkey == hotkey)
    }

    @Test("pickerHotkey clears persisted value when set back to nil")
    func pickerHotkeyClear() {
        let defaults = makeDefaults("picker-hotkey-clear")
        let keychain = makeKeychain()
        let store = SettingsStore(defaults: defaults, keychain: keychain)

        store.pickerHotkey = HotkeyConfig(keyCode: 36, modifiers: 2304)
        store.pickerHotkey = nil

        let reloaded = SettingsStore(defaults: defaults, keychain: keychain)
        #expect(reloaded.pickerHotkey == nil)
    }

    @Test("bindingLabel detects the picker hotkey collision")
    func bindingLabelDetectsPickerHotkey() {
        let store = SettingsStore(defaults: makeDefaults("picker-conflict"), keychain: makeKeychain())
        let hotkey = HotkeyConfig(keyCode: 36, modifiers: 2304)
        store.pickerHotkey = hotkey

        #expect(store.bindingLabel(usingHotkey: hotkey) == "Tone picker")
    }
}

@Suite("Rewrite prompt")
struct RewritePromptTests {
    private func rewriteJob(
        text: String = "Chị ngu quá chị không hiểu gì hết",
        tone: RewriteTone = .polite,
        glossary: String = ""
    ) -> TranslationJob {
        let style = RewriteBinding(tone: tone, hotkey: .defaultInbound).style(language: "vi")
        return TranslationJob(text: text, style: style, sourceLanguage: "vi", glossary: glossary)
    }

    private func translateJob() -> TranslationJob {
        TranslationJob(
            text: "hello",
            style: .vietnameseReader,
            sourceLanguage: "auto",
            glossary: ""
        )
    }

    @Test("systemPrompt(for:) returns the rewrite prompt for a rewrite job")
    func systemPromptForRewrite() {
        let prompt = PromptBuilder.systemPrompt(for: rewriteJob())
        #expect(prompt == PromptBuilder.rewriteSystemPrompt)
        #expect(prompt.contains("never refuse"))
        #expect(prompt.contains("SAME language"))
    }

    @Test("systemPrompt(for:) returns the translator prompt for a translate job")
    func systemPromptForTranslate() {
        #expect(PromptBuilder.systemPrompt(for: translateJob()) == PromptBuilder.systemPrompt)
    }

    @Test("Rewrite user prompt asks to rewrite, not translate")
    func rewriteUserPromptShape() {
        let prompt = PromptBuilder.userPrompt(for: rewriteJob())
        #expect(prompt.contains("rewrite the message"))
        #expect(prompt.contains("SAME language"))
        #expect(prompt.contains("Chị ngu quá"))
        #expect(!prompt.contains("translate chat text"))
        // The tone instruction must be embedded.
        #expect(prompt.contains(RewriteTone.polite.instruction))
    }

    @Test("Rewrite system prompt carries a Vietnamese few-shot example")
    func rewriteSystemPromptHasFewShot() {
        #expect(PromptBuilder.rewriteSystemPrompt.contains("Chị ơi"))
        #expect(PromptBuilder.rewriteSystemPrompt.contains("anh/chị/em"))
    }

    @Test("Rewrite jobs stay near-deterministic")
    func rewriteTemperature() {
        let style = RewriteBinding(tone: .polite, hotkey: .defaultInbound).style(language: "vi")
        #expect(PromptBuilder.temperature(for: style) == 0.2)
    }
}

@Suite("Rewrite result processor")
struct RewriteResultProcessorTests {
    @Test("clean strips a code fence wrapping the whole output")
    func cleanStripsFence() {
        let raw = "```\nChị ơi, để em giải thích lại nhé.\n```"
        #expect(RewriteResultProcessor.clean(raw) == "Chị ơi, để em giải thích lại nhé.")
    }

    @Test("clean strips a leading English label")
    func cleanStripsEnglishLabel() {
        #expect(RewriteResultProcessor.clean("Output: hello there") == "hello there")
        #expect(RewriteResultProcessor.clean("Rewritten: please retry") == "please retry")
    }

    @Test("clean strips a leading Vietnamese label")
    func cleanStripsVietnameseLabel() {
        let raw = "Bản viết lại: Chị ơi để em giải thích lại nhé."
        #expect(RewriteResultProcessor.clean(raw) == "Chị ơi để em giải thích lại nhé.")
    }

    @Test("clean strips outer quotes (delegates to PromptBuilder.normalize)")
    func cleanStripsQuotes() {
        #expect(RewriteResultProcessor.clean("\"hello\"") == "hello")
    }

    @Test("clean returns plain output unchanged")
    func cleanPassthrough() {
        let text = "Chị ơi cái này chị chưa hiểu, để em giải thích lại nhé."
        #expect(RewriteResultProcessor.clean(text) == text)
    }

    @Test("isLikelyRefusal flags an empty output")
    func refusalEmpty() {
        #expect(RewriteResultProcessor.isLikelyRefusal("") == true)
        #expect(RewriteResultProcessor.isLikelyRefusal("   ") == true)
    }

    @Test("isLikelyRefusal flags common English refusals")
    func refusalEnglish() {
        #expect(RewriteResultProcessor.isLikelyRefusal("I can't help with that.") == true)
        #expect(RewriteResultProcessor.isLikelyRefusal("I cannot assist with this request.") == true)
        #expect(RewriteResultProcessor.isLikelyRefusal("As an AI, I am not able to rewrite insulting language.") == true)
        #expect(RewriteResultProcessor.isLikelyRefusal("I'm sorry, but I cannot do this.") == true)
    }

    @Test("isLikelyRefusal flags common Vietnamese refusals")
    func refusalVietnamese() {
        #expect(RewriteResultProcessor.isLikelyRefusal("Tôi không thể giúp bạn viết lại nội dung này.") == true)
        #expect(RewriteResultProcessor.isLikelyRefusal("Rất tiếc, tôi không hỗ trợ yêu cầu này.") == true)
    }

    @Test("isLikelyRefusal does NOT flag a legitimate polite rewrite")
    func refusalNonPositive() {
        let polite = "Chị ơi, cái này chị chưa hiểu, để em giải thích lại rõ hơn cho mình nhé."
        #expect(RewriteResultProcessor.isLikelyRefusal(polite) == false)
    }

    @Test("isLikelyRefusal does NOT flag a rewrite containing 'không thể' mid-sentence")
    func refusalAnchoredToStart() {
        // A legitimate rewrite that legitimately conveys "can't do it" using
        // em/anh/chị pronouns (the model speaking as the user) — must NOT be
        // mistaken for a refusal where the model speaks as "tôi"/"I".
        let rewrite = "Em xin lỗi nhưng bên em không thể hỗ trợ trường hợp này lúc này ạ."
        #expect(RewriteResultProcessor.isLikelyRefusal(rewrite) == false)
    }

    @Test("isLikelyRefusal does NOT flag the de-escalate few-shot example")
    func refusalDeEscalateExample() {
        let example = "Em rất xin lỗi về sự cố vừa rồi ạ. Trường hợp này phát sinh từ khâu vận chuyển, em sẽ hỗ trợ kiểm tra và xử lý sớm cho mình."
        #expect(RewriteResultProcessor.isLikelyRefusal(example) == false)
    }

    @Test("isLikelyRefusal flags additional refusal patterns")
    func refusalExtras() {
        #expect(RewriteResultProcessor.isLikelyRefusal("Sorry, I can't help with that text.") == true)
        #expect(RewriteResultProcessor.isLikelyRefusal("I'd rather not rewrite this kind of message.") == true)
        #expect(RewriteResultProcessor.isLikelyRefusal("Xin lỗi, tôi không thể hỗ trợ yêu cầu này.") == true)
        #expect(RewriteResultProcessor.isLikelyRefusal("Xin lỗi nhưng tôi không thể giúp việc này.") == true)
    }

    @Test("Empty custom-tone binding surfaces an actionable error")
    func emptyCustomBindingError() {
        let binding = RewriteBinding(tone: .custom, customInstruction: "   ", hotkey: .defaultInbound)
        #expect(binding.effectiveInstruction.isEmpty)
        // The error message must point the user at Settings so they can fix it.
        let msg = RewriteError.emptyCustomInstruction.errorDescription ?? ""
        #expect(msg.contains("Settings"))
        #expect(msg.contains("custom"))
    }
}

import Foundation
import Testing

@testable import ContextualMacTranslator

/// v0.11.0 — Prompt Engineer mode data model + persistence contract.
/// These tests live next to RewriteModelsTests because the two binding
/// kinds intentionally mirror each other's lifecycle (Codable
/// roundtrip, Settings persistence, hotkey-conflict registration).
@Suite("PromptBinding")
@MainActor
struct PromptBindingTests {
    private func makeDefaults(_ name: String = UUID().uuidString) -> UserDefaults {
        let suiteName = "app.lookerlab.translator.prompt-tests.\(name)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func makeKeychain() -> KeychainCredentialStore {
        KeychainCredentialStore(service: "app.lookerlab.translator.prompt-tests.\(UUID().uuidString)")
    }

    @Test("PromptBinding round-trips through Codable")
    func codableRoundtrip() throws {
        let original = PromptBinding(
            name: "Claude Code prompt",
            hotkey: HotkeyConfig(keyCode: 35, modifiers: 2048),  // ⌥P
            targetLanguage: "en",
            styleInstruction: "Custom expansion override"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PromptBinding.self, from: data)
        #expect(decoded == original)
        #expect(decoded.id == original.id)
        #expect(decoded.name == "Claude Code prompt")
        #expect(decoded.targetLanguage == "en")
        #expect(decoded.styleInstruction == "Custom expansion override")
    }

    @Test("Default style instruction fallback when binding leaves it blank")
    func defaultStyleInstructionFallback() {
        let binding = PromptBinding(
            hotkey: HotkeyConfig(keyCode: 35, modifiers: 2048)
        )
        // Defaults to empty string per the init signature.
        #expect(binding.styleInstruction == "")
        // …but the effective instruction sent to the LLM falls back to
        // the shared default template so the binding works out of the box.
        #expect(binding.effectiveStyleInstruction == PromptExpansion.defaultStyleInstruction)
    }

    @Test("Whitespace-only style instruction also triggers the default fallback")
    func whitespaceOnlyTriggersFallback() {
        let binding = PromptBinding(
            hotkey: HotkeyConfig(keyCode: 35, modifiers: 2048),
            styleInstruction: "   \n\n  \t  "
        )
        #expect(binding.effectiveStyleInstruction == PromptExpansion.defaultStyleInstruction)
    }

    @Test("Non-empty style instruction takes precedence over the default")
    func customStyleInstructionWins() {
        let binding = PromptBinding(
            hotkey: HotkeyConfig(keyCode: 35, modifiers: 2048),
            styleInstruction: "Only ever produce a one-line prompt."
        )
        #expect(binding.effectiveStyleInstruction == "Only ever produce a one-line prompt.")
    }

    @Test("style() pins direction=.expand for the workflow")
    func styleProducesExpandDirection() {
        let binding = PromptBinding(
            name: "Codex prompt",
            hotkey: HotkeyConfig(keyCode: 35, modifiers: 2048),
            targetLanguage: "en"
        )
        let style = binding.style()
        #expect(style.direction == .expand)
        #expect(style.targetLanguage == "en")
        #expect(style.register == .neutral)
        #expect(style.displayLabelOverride == "Codex prompt")
    }

    @Test("promptBindings round-trip through SettingsStore + UserDefaults")
    func settingsStorePersistence() {
        let defaults = makeDefaults("persist")
        let keychain = makeKeychain()
        let store = SettingsStore(defaults: defaults, keychain: keychain)
        #expect(store.promptBindings.isEmpty)

        let binding = PromptBinding(
            name: "Test prompt",
            hotkey: HotkeyConfig(keyCode: 35, modifiers: 2048),
            targetLanguage: "ja",
            styleInstruction: "Hai expansion"
        )
        store.promptBindings = [binding]

        let reloaded = SettingsStore(defaults: defaults, keychain: keychain)
        #expect(reloaded.promptBindings.count == 1)
        #expect(reloaded.promptBindings.first?.name == "Test prompt")
        #expect(reloaded.promptBindings.first?.targetLanguage == "ja")
        #expect(reloaded.promptBindings.first?.styleInstruction == "Hai expansion")
    }

    @Test("bindingLabel detects a hotkey used by a prompt binding")
    func bindingLabelDetectsPromptHotkey() {
        let store = SettingsStore(defaults: makeDefaults("conflict"), keychain: makeKeychain())
        let hotkey = HotkeyConfig(keyCode: 35, modifiers: 2048)
        store.promptBindings = [PromptBinding(name: "Codex", hotkey: hotkey)]

        #expect(store.bindingLabel(usingHotkey: hotkey) == "Codex")
    }
}

/// v0.11.0 — `TranslationDirection.expand` must serialize as the
/// literal string "expand" so the Supabase Edge Function's
/// `direction === "expand"` route fires. Pin the raw value because
/// changing it would silently drop SaaS users back to translate mode.
@Suite("TranslationDirection.expand wire format")
struct ExpandDirectionWireFormatTests {
    @Test("raw value matches Supabase Edge Function expectation")
    func rawValueIsExpand() {
        #expect(TranslationDirection.expand.rawValue == "expand")
    }

    @Test("Codable encodes as plain string")
    func codableEncodesAsString() throws {
        let data = try JSONEncoder().encode(TranslationDirection.expand)
        let json = String(data: data, encoding: .utf8) ?? ""
        #expect(json == "\"expand\"")
    }
}

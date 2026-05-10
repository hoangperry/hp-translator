import Carbon.HIToolbox
import Foundation
import Testing

@testable import ContextualMacTranslator

// MARK: - Settings store v0.3 fields

@Suite("SettingsStore — v0.3 multi-language")
@MainActor
struct SettingsStoreV3Tests {
    private func makeStore() -> SettingsStore {
        let suiteName = "translator-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let keychain = KeychainCredentialStore(service: "translator-tests.\(UUID().uuidString)")
        return SettingsStore(defaults: defaults, keychain: keychain)
    }

    @Test("primaryLanguage defaults to vi (back-compat)")
    func primaryDefaultsToVi() {
        #expect(makeStore().primaryLanguage == "vi")
    }

    @Test("Default outbound bindings reproduce v0.2 keigo + casual hotkeys")
    func defaultOutboundBindings() {
        let store = makeStore()
        #expect(store.outboundBindings.count == 2)
        #expect(store.outboundBindings.contains { $0 == .defaultJapaneseFormal })
        #expect(store.outboundBindings.contains { $0 == .defaultJapaneseCasual })
    }

    @Test("Default inbound binding = ⌥D")
    func defaultInbound() {
        #expect(makeStore().inboundBinding == .default)
        #expect(makeStore().inboundBinding.hotkey == .defaultInbound)
    }

    @Test("Round-trips outbound bindings via UserDefaults")
    func bindingsPersist() {
        let suiteName = "translator-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let keychain = KeychainCredentialStore(service: "translator-tests.\(UUID().uuidString)")

        let store = SettingsStore(defaults: defaults, keychain: keychain)
        store.outboundBindings.append(OutboundBinding(
            languageCode: "ko",
            register: .formal,
            hotkey: HotkeyConfig(keyCode: kVK_ANSI_Q, modifiers: cmdKey)
        ))

        let reloaded = SettingsStore(defaults: defaults, keychain: keychain)
        #expect(reloaded.outboundBindings.count == 3)
        #expect(reloaded.outboundBindings.last?.languageCode == "ko")
    }

    @Test("DeepL + LibreTranslate credentials persist via Keychain")
    func newProviderCredsPersist() {
        let suiteName = "translator-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let keychain = KeychainCredentialStore(service: "translator-tests.\(UUID().uuidString)")

        let store = SettingsStore(defaults: defaults, keychain: keychain)
        store.deeplAPIKey = "deepl-key"
        store.deeplUseFree = false
        store.libreTranslateBaseURL = "https://my-libre.example.com"
        store.libreTranslateAPIKey = "libre-key"

        let reloaded = SettingsStore(defaults: defaults, keychain: keychain)
        #expect(reloaded.deeplAPIKey == "deepl-key")
        #expect(reloaded.deeplUseFree == false)
        #expect(reloaded.libreTranslateBaseURL == "https://my-libre.example.com")
        #expect(reloaded.libreTranslateAPIKey == "libre-key")
    }
}

// MARK: - HotkeyConfig display

@Suite("HotkeyConfig.displayLabel")
struct HotkeyDisplayTests {
    @Test("Default inbound = ⌥D")
    func inboundLabel() {
        #expect(HotkeyConfig.defaultInbound.displayLabel == "⌥D")
    }

    @Test("Default outbound formal = ⌘⏎")
    func outboundFormalLabel() {
        #expect(HotkeyConfig.defaultOutboundFormal.displayLabel == "⌘⏎")
    }

    @Test("Default outbound casual = ⌥⏎")
    func outboundCasualLabel() {
        #expect(HotkeyConfig.defaultOutboundCasual.displayLabel == "⌥⏎")
    }

    @Test("Multiple modifiers stack in conventional order ⌃⌥⇧⌘")
    func multipleModifiers() {
        let cfg = HotkeyConfig(
            keyCode: UInt32(kVK_ANSI_E),
            modifiers: UInt32(controlKey | optionKey | shiftKey | cmdKey)
        )
        #expect(cfg.displayLabel == "⌃⌥⇧⌘E")
    }

    @Test("Codable round-trip preserves keyCode + modifiers")
    func codableRoundTrip() throws {
        let original = HotkeyConfig.defaultOutboundFormal
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HotkeyConfig.self, from: data)
        #expect(decoded == original)
    }
}

// MARK: - TranslationStyle

@Suite("TranslationStyle")
struct TranslationStyleTests {
    @Test("Outbound formal sets previewByDefault = true")
    func formalPreviews() {
        let style = TranslationStyle(direction: .outbound, targetLanguage: "ko", register: .formal)
        #expect(style.previewByDefault == true)
    }

    @Test("Outbound casual auto-sends (preview = false)")
    func casualAutoSends() {
        let style = TranslationStyle(direction: .outbound, targetLanguage: "ko", register: .casual)
        #expect(style.previewByDefault == false)
    }

    @Test("Inbound never previews regardless of register")
    func inboundNoPreview() {
        for register in Register.allCases {
            let style = TranslationStyle(direction: .inbound, targetLanguage: "vi", register: register)
            #expect(style.previewByDefault == false)
        }
    }

    @Test("rawValue keeps legacy strings for back-compat")
    func legacyRawValues() {
        #expect(TranslationStyle.vietnameseReader.rawValue == "vietnameseReader")
        #expect(TranslationStyle.japaneseBusiness.rawValue == "japaneseBusiness")
        #expect(TranslationStyle.japaneseCasual.rawValue == "japaneseCasual")
    }

    @Test("New language pairs get a stable derived rawValue")
    func newLangRawValue() {
        let koFormal = TranslationStyle(direction: .outbound, targetLanguage: "ko", register: .formal)
        #expect(koFormal.rawValue == "outbound-ko-formal")
    }

    @Test("Style instruction mentions target language name")
    func styleMentionsLang() {
        let frFormal = TranslationStyle(direction: .outbound, targetLanguage: "fr", register: .formal)
        #expect(frFormal.styleInstruction.contains("French"))
    }
}

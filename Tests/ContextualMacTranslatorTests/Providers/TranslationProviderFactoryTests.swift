import Foundation
import Testing

@testable import ContextualMacTranslator

@MainActor
private func makeSettings(_ configure: (SettingsStore) -> Void = { _ in }) -> SettingsStore {
    let suiteName = "translator-tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    let keychain = KeychainCredentialStore(service: "translator-tests.\(UUID().uuidString)")
    let store = SettingsStore(defaults: defaults, keychain: keychain)
    configure(store)
    return store
}

@Suite("TranslationProviderFactory")
@MainActor
struct TranslationProviderFactoryTests {
    @Test("Custom backend mode returns BackendProvider against settings.endpoint")
    func customBackendMode() {
        let settings = makeSettings { store in
            store.translationSource = .customBackend
            store.endpoint = "http://127.0.0.1:8765/translate"
            store.apiKey = "abc"
        }
        let factory = TranslationProviderFactory(settings: settings)

        let provider = factory.make()
        #expect(provider is BackendProvider)
        #expect(provider.isConfigured == true)
    }

    @Test("1st-party backend mode reads firstPartyEndpoint, ignores custom endpoint")
    func firstPartyMode() {
        let settings = makeSettings { store in
            store.translationSource = .firstPartyBackend
            store.endpoint = "http://customer.example.com/translate"
            store.apiKey = "custom-token"
            store.firstPartyEndpoint = "https://translator.lookerlab.app/translate"
            store.firstPartyToken = "issued-token"
        }
        let factory = TranslationProviderFactory(settings: settings)

        let provider = factory.make()
        let backend = try? #require(provider as? BackendProvider)
        #expect(backend?.isConfigured == true)
        // Switching to custom would expose the customer endpoint; isConfigured
        // alone can't prove which slot was read but we can flip 1st-party empty
        // and confirm isConfigured drops.
        settings.firstPartyEndpoint = ""
        let provider2 = factory.make()
        #expect(provider2.isConfigured == false)
    }

    @Test("Direct + Gemini selects GeminiDirectProvider with stored creds")
    func directGemini() {
        let settings = makeSettings { store in
            store.translationSource = .directAPI
            store.directProvider = .gemini
            store.geminiAPIKey = "test-key"
        }
        let factory = TranslationProviderFactory(settings: settings)

        let provider = factory.make()
        #expect(provider is GeminiDirectProvider)
        #expect(provider.isConfigured == true)
    }

    @Test("Direct + Ollama uses defaults when no overrides set")
    func directOllamaDefaults() {
        let settings = makeSettings { store in
            store.translationSource = .directAPI
            store.directProvider = .ollama
        }
        let factory = TranslationProviderFactory(settings: settings)

        let provider = factory.make()
        #expect(provider is OllamaDirectProvider)
        // baseURL + model both default → configured = true (no creds needed for Ollama)
        #expect(provider.isConfigured == true)
    }

    @Test("Direct + GoogleTranslate isConfigured gates on apiKey")
    func directGoogleTranslate() {
        let settings = makeSettings { store in
            store.translationSource = .directAPI
            store.directProvider = .googleTranslate
        }
        let factory = TranslationProviderFactory(settings: settings)

        #expect(factory.make().isConfigured == false)

        settings.googleTranslateAPIKey = "k"
        #expect(factory.make().isConfigured == true)
    }

    @Test("Direct + OpenAI-compat passes through every config field")
    func directOpenAICompat() {
        let settings = makeSettings { store in
            store.translationSource = .directAPI
            store.directProvider = .openAICompatible
            store.openAICompatBaseURL = "https://router.example.com/v1"
            store.openAICompatAPIKey = "sk-x"
            store.openAICompatModel = "claude-test"
        }
        let factory = TranslationProviderFactory(settings: settings)

        let provider = factory.make()
        #expect(provider is OpenAICompatibleDirectProvider)
        #expect(provider.isConfigured == true)
    }

    @Test("Direct + Mock works with no setup")
    func directMock() {
        let settings = makeSettings { store in
            store.translationSource = .directAPI
            store.directProvider = .mock
        }
        let factory = TranslationProviderFactory(settings: settings)

        let provider = factory.make()
        #expect(provider is MockDirectProvider)
        #expect(provider.isConfigured == true)
    }

    @Test("Direct + GeminiCLI dispatches to GeminiCLIProvider")
    func directGeminiCLI() {
        let settings = makeSettings { store in
            store.translationSource = .directAPI
            store.directProvider = .geminiCLI
        }
        let factory = TranslationProviderFactory(settings: settings)
        #expect(factory.make() is GeminiCLIProvider)
    }

    @Test("Direct + CodexCLI dispatches to CodexCLIProvider")
    func directCodexCLI() {
        let settings = makeSettings { store in
            store.translationSource = .directAPI
            store.directProvider = .codexCLI
        }
        let factory = TranslationProviderFactory(settings: settings)
        #expect(factory.make() is CodexCLIProvider)
    }

    @Test("Switching source picks a different provider on next make()")
    func switchingSourceReflectsImmediately() {
        let settings = makeSettings { store in
            store.translationSource = .customBackend
            store.endpoint = "http://127.0.0.1:8765/translate"
        }
        let factory = TranslationProviderFactory(settings: settings)

        #expect(factory.make() is BackendProvider)

        settings.translationSource = .directAPI
        settings.directProvider = .mock
        #expect(factory.make() is MockDirectProvider)
    }
}

@Suite("SettingsStore — Phase 3e fields")
@MainActor
struct SettingsStorePhase3eTests {
    @Test("translationSource defaults to customBackend (back-compat)")
    func defaultSource() {
        let settings = makeSettings()
        #expect(settings.translationSource == .customBackend)
    }

    @Test("directProvider defaults to gemini")
    func defaultDirect() {
        let settings = makeSettings()
        #expect(settings.directProvider == .gemini)
    }

    @Test("Per-provider model defaults match server constants")
    func providerDefaults() {
        let settings = makeSettings()
        #expect(settings.geminiModel == "gemini-2.5-flash")
        #expect(settings.ollamaBaseURL == "http://127.0.0.1:11434")
        #expect(settings.ollamaModel == "qwen2.5:7b-instruct")
        #expect(settings.openAICompatBaseURL == "https://api.openai.com/v1")
        #expect(settings.openAICompatModel == "gpt-4.1-mini")
    }

    @Test("translationSource persists across SettingsStore instances")
    func sourcePersists() {
        let suiteName = "translator-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let keychain = KeychainCredentialStore(service: "translator-tests.\(UUID().uuidString)")

        let store = SettingsStore(defaults: defaults, keychain: keychain)
        store.translationSource = .directAPI
        store.directProvider = .ollama

        let reloaded = SettingsStore(defaults: defaults, keychain: keychain)
        #expect(reloaded.translationSource == .directAPI)
        #expect(reloaded.directProvider == .ollama)
    }

    @Test("Per-provider Keychain values persist + isolated per account")
    func keychainSlotsIsolated() {
        let suiteName = "translator-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let keychain = KeychainCredentialStore(service: "translator-tests.\(UUID().uuidString)")

        let store = SettingsStore(defaults: defaults, keychain: keychain)
        store.geminiAPIKey = "gemini-key"
        store.googleTranslateAPIKey = "translate-key"
        store.openAICompatAPIKey = "openai-key"
        store.firstPartyToken = "firstparty-token"
        store.apiKey = "custom-token"

        let reloaded = SettingsStore(defaults: defaults, keychain: keychain)
        #expect(reloaded.geminiAPIKey == "gemini-key")
        #expect(reloaded.googleTranslateAPIKey == "translate-key")
        #expect(reloaded.openAICompatAPIKey == "openai-key")
        #expect(reloaded.firstPartyToken == "firstparty-token")
        #expect(reloaded.apiKey == "custom-token")
    }

    @Test("Existing endpoint + apiKey survive upgrade to Phase 3e schema")
    func backwardCompat() {
        let suiteName = "translator-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        // Pre-seed defaults as if the user upgraded from Phase 2.5 schema.
        defaults.set("https://example.com/translate", forKey: "translator.endpoint")
        let keychain = KeychainCredentialStore(service: "translator-tests.\(UUID().uuidString)")
        try? keychain.write("legacy-token", account: "default-bearer-token")

        let store = SettingsStore(defaults: defaults, keychain: keychain)
        // No `translator.source` key was set → factory should default to
        // .customBackend so the user keeps their existing config.
        #expect(store.translationSource == .customBackend)
        #expect(store.endpoint == "https://example.com/translate")
        #expect(store.apiKey == "legacy-token")
    }
}

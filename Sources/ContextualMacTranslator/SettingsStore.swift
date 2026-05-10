import Foundation
import OSLog

@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    /// Bundle-scoped service identifier used for Keychain entries.
    /// Matches `CFBundleIdentifier` in `scripts/package_app.sh`.
    static let keychainService = "app.lookerlab.translator"

    // MARK: Source picker (Phase 3e)

    @Published var translationSource: TranslationSource {
        didSet {
            guard translationSource != oldValue else { return }
            defaults.set(translationSource.rawValue, forKey: Keys.translationSource)
        }
    }

    @Published var directProvider: DirectProviderKind {
        didSet {
            guard directProvider != oldValue else { return }
            defaults.set(directProvider.rawValue, forKey: Keys.directProvider)
        }
    }

    // MARK: Custom backend (legacy `endpoint` + `apiKey`)

    @Published var endpoint: String {
        didSet {
            guard endpoint != oldValue else { return }
            defaults.set(endpoint, forKey: Keys.endpoint)
        }
    }

    @Published var apiKey: String {
        didSet {
            guard apiKey != oldValue else { return }
            writeKeychain(apiKey, account: Accounts.apiKey)
        }
    }

    // MARK: 1st-party backend (separate slot so user can switch without re-entering)

    @Published var firstPartyEndpoint: String {
        didSet {
            guard firstPartyEndpoint != oldValue else { return }
            defaults.set(firstPartyEndpoint, forKey: Keys.firstPartyEndpoint)
        }
    }

    @Published var firstPartyToken: String {
        didSet {
            guard firstPartyToken != oldValue else { return }
            writeKeychain(firstPartyToken, account: Accounts.firstPartyToken)
        }
    }

    // MARK: Direct providers — Gemini

    @Published var geminiAPIKey: String {
        didSet {
            guard geminiAPIKey != oldValue else { return }
            writeKeychain(geminiAPIKey, account: Accounts.geminiAPIKey)
        }
    }

    @Published var geminiModel: String {
        didSet {
            guard geminiModel != oldValue else { return }
            defaults.set(geminiModel, forKey: Keys.geminiModel)
        }
    }

    // MARK: Direct providers — Ollama

    @Published var ollamaBaseURL: String {
        didSet {
            guard ollamaBaseURL != oldValue else { return }
            defaults.set(ollamaBaseURL, forKey: Keys.ollamaBaseURL)
        }
    }

    @Published var ollamaModel: String {
        didSet {
            guard ollamaModel != oldValue else { return }
            defaults.set(ollamaModel, forKey: Keys.ollamaModel)
        }
    }

    // MARK: Direct providers — Google Translate

    @Published var googleTranslateAPIKey: String {
        didSet {
            guard googleTranslateAPIKey != oldValue else { return }
            writeKeychain(googleTranslateAPIKey, account: Accounts.googleTranslateAPIKey)
        }
    }

    // MARK: Direct providers — OpenAI-compatible

    @Published var openAICompatBaseURL: String {
        didSet {
            guard openAICompatBaseURL != oldValue else { return }
            defaults.set(openAICompatBaseURL, forKey: Keys.openAICompatBaseURL)
        }
    }

    @Published var openAICompatAPIKey: String {
        didSet {
            guard openAICompatAPIKey != oldValue else { return }
            writeKeychain(openAICompatAPIKey, account: Accounts.openAICompatAPIKey)
        }
    }

    @Published var openAICompatModel: String {
        didSet {
            guard openAICompatModel != oldValue else { return }
            defaults.set(openAICompatModel, forKey: Keys.openAICompatModel)
        }
    }

    // MARK: Shared / advanced

    @Published var glossary: String {
        didSet {
            guard glossary != oldValue else { return }
            writeKeychain(glossary, account: Accounts.glossary)
        }
    }

    @Published var focusGuardEnabled: Bool {
        didSet {
            guard focusGuardEnabled != oldValue else { return }
            defaults.set(focusGuardEnabled, forKey: Keys.focusGuardEnabled)
        }
    }

    @Published var firstRunCompleted: Bool {
        didSet {
            guard firstRunCompleted != oldValue else { return }
            defaults.set(firstRunCompleted, forKey: Keys.firstRunCompleted)
        }
    }

    // MARK: Multi-language (v0.3 / Phase 8)

    /// User's primary readable language (BCP47). Inbound translations
    /// always target this; outbound translations use this as the source.
    @Published var primaryLanguage: String {
        didSet {
            guard primaryLanguage != oldValue else { return }
            defaults.set(primaryLanguage, forKey: Keys.primaryLanguage)
        }
    }

    /// Hotkey for inbound translation (selection → primary language).
    @Published var inboundBinding: InboundBinding {
        didSet {
            guard inboundBinding != oldValue else { return }
            persist(inboundBinding, forKey: Keys.inboundBinding)
        }
    }

    /// Outbound translation bindings. Each entry = (target language +
    /// register + hotkey + optional custom style instruction). Defaults
    /// reproduce v0.2 keigo + casual hotkeys for back-compat.
    @Published var outboundBindings: [OutboundBinding] {
        didSet {
            guard outboundBindings != oldValue else { return }
            persist(outboundBindings, forKey: Keys.outboundBindings)
        }
    }

    // MARK: Direct providers — DeepL (v0.3)

    @Published var deeplAPIKey: String {
        didSet {
            guard deeplAPIKey != oldValue else { return }
            writeKeychain(deeplAPIKey, account: Accounts.deeplAPIKey)
        }
    }

    /// `true` = use Free endpoint (api-free.deepl.com), `false` = Pro
    /// (api.deepl.com). Free is the common case so default true.
    @Published var deeplUseFree: Bool {
        didSet {
            guard deeplUseFree != oldValue else { return }
            defaults.set(deeplUseFree, forKey: Keys.deeplUseFree)
        }
    }

    // MARK: Direct providers — LibreTranslate (v0.3)

    @Published var libreTranslateBaseURL: String {
        didSet {
            guard libreTranslateBaseURL != oldValue else { return }
            defaults.set(libreTranslateBaseURL, forKey: Keys.libreTranslateBaseURL)
        }
    }

    @Published var libreTranslateAPIKey: String {
        didSet {
            guard libreTranslateAPIKey != oldValue else { return }
            writeKeychain(libreTranslateAPIKey, account: Accounts.libreTranslateAPIKey)
        }
    }

    // MARK: Internals

    private let defaults: UserDefaults
    private let keychain: KeychainCredentialStore
    private static let logger = Logger(subsystem: SettingsStore.keychainService, category: "settings")

    private enum Keys {
        // Source picker
        static let translationSource = "translator.source"
        static let directProvider = "translator.direct.provider"
        // Custom backend (legacy)
        static let endpoint = "translator.endpoint"
        static let apiKey = "translator.apiKey"
        // 1st-party backend
        static let firstPartyEndpoint = "translator.firstParty.endpoint"
        // Gemini
        static let geminiModel = "translator.gemini.model"
        // Ollama
        static let ollamaBaseURL = "translator.ollama.baseURL"
        static let ollamaModel = "translator.ollama.model"
        // OpenAI-compatible
        static let openAICompatBaseURL = "translator.openAICompat.baseURL"
        static let openAICompatModel = "translator.openAICompat.model"
        // Shared
        static let glossary = "translator.glossary"
        static let focusGuardEnabled = "translator.focusGuardEnabled"
        static let firstRunCompleted = "translator.firstRunCompleted"
        // v0.3 multi-lang
        static let primaryLanguage = "translator.primaryLanguage"
        static let inboundBinding = "translator.inboundBinding"
        static let outboundBindings = "translator.outboundBindings"
        // v0.3 new providers
        static let deeplUseFree = "translator.deepl.useFree"
        static let libreTranslateBaseURL = "translator.libretranslate.baseURL"
    }

    private enum Accounts {
        // Custom backend
        static let apiKey = "default-bearer-token"
        // 1st-party backend
        static let firstPartyToken = "firstparty-bearer-token"
        // Direct providers
        static let geminiAPIKey = "gemini-api-key"
        static let googleTranslateAPIKey = "google-translate-api-key"
        static let openAICompatAPIKey = "openai-compatible-api-key"
        static let deeplAPIKey = "deepl-api-key"
        static let libreTranslateAPIKey = "libretranslate-api-key"
        // Shared
        static let glossary = "default-glossary"
    }

    /// Default endpoint points to the reference backend running locally so
    /// first-launch with `translator-server` running on the same machine
    /// works without manual config. Users override in Settings for remote
    /// backends.
    static let defaultEndpoint = "http://127.0.0.1:8765/translate"

    /// Per-provider built-in defaults. Mirrors Python server defaults so
    /// switching from backend mode to direct mode keeps the same model.
    enum ProviderDefaults {
        static let geminiModel = "gemini-2.5-flash"
        static let ollamaBaseURL = "http://127.0.0.1:11434"
        static let ollamaModel = "qwen2.5:7b-instruct"
        static let openAICompatBaseURL = "https://api.openai.com/v1"
        static let openAICompatModel = "gpt-4.1-mini"
        static let libreTranslateBaseURL = "https://libretranslate.com"
    }

    init(
        defaults: UserDefaults = .standard,
        keychain: KeychainCredentialStore = KeychainCredentialStore(service: SettingsStore.keychainService)
    ) {
        self.defaults = defaults
        self.keychain = keychain

        // Migrate legacy UserDefaults secrets to Keychain on first launch.
        let migration = CredentialMigration(store: keychain, defaults: defaults)
        Self.migrateSecret(migration, key: Keys.apiKey, account: Accounts.apiKey)
        Self.migrateSecret(migration, key: Keys.glossary, account: Accounts.glossary)

        // Source picker — default to .customBackend so existing installs
        // keep their endpoint/apiKey config without UI churn.
        let storedSource = defaults.string(forKey: Keys.translationSource).flatMap(TranslationSource.init(rawValue:))
        translationSource = storedSource ?? .customBackend

        let storedDirect = defaults.string(forKey: Keys.directProvider).flatMap(DirectProviderKind.init(rawValue:))
        directProvider = storedDirect ?? .gemini

        // Custom backend (existing behaviour)
        endpoint = defaults.string(forKey: Keys.endpoint) ?? Self.defaultEndpoint
        apiKey = (try? keychain.read(account: Accounts.apiKey)) ?? ""

        // 1st-party backend
        firstPartyEndpoint = defaults.string(forKey: Keys.firstPartyEndpoint) ?? ""
        firstPartyToken = (try? keychain.read(account: Accounts.firstPartyToken)) ?? ""

        // Direct providers
        geminiAPIKey = (try? keychain.read(account: Accounts.geminiAPIKey)) ?? ""
        geminiModel = defaults.string(forKey: Keys.geminiModel) ?? ProviderDefaults.geminiModel

        ollamaBaseURL = defaults.string(forKey: Keys.ollamaBaseURL) ?? ProviderDefaults.ollamaBaseURL
        ollamaModel = defaults.string(forKey: Keys.ollamaModel) ?? ProviderDefaults.ollamaModel

        googleTranslateAPIKey = (try? keychain.read(account: Accounts.googleTranslateAPIKey)) ?? ""

        openAICompatBaseURL = defaults.string(forKey: Keys.openAICompatBaseURL) ?? ProviderDefaults.openAICompatBaseURL
        openAICompatAPIKey = (try? keychain.read(account: Accounts.openAICompatAPIKey)) ?? ""
        openAICompatModel = defaults.string(forKey: Keys.openAICompatModel) ?? ProviderDefaults.openAICompatModel

        // Shared
        glossary = (try? keychain.read(account: Accounts.glossary)) ?? ""
        focusGuardEnabled = defaults.object(forKey: Keys.focusGuardEnabled) as? Bool ?? true
        firstRunCompleted = defaults.bool(forKey: Keys.firstRunCompleted)

        // v0.3 multi-lang — back-compat defaults match v0.2 hardcoded behaviour
        primaryLanguage = defaults.string(forKey: Keys.primaryLanguage) ?? "vi"
        inboundBinding = Self.loadCodable(InboundBinding.self, defaults: defaults, key: Keys.inboundBinding)
            ?? .default
        outboundBindings = Self.loadCodable([OutboundBinding].self, defaults: defaults, key: Keys.outboundBindings)
            ?? [.defaultJapaneseFormal, .defaultJapaneseCasual]

        // v0.3 new providers
        deeplAPIKey = (try? keychain.read(account: Accounts.deeplAPIKey)) ?? ""
        deeplUseFree = defaults.object(forKey: Keys.deeplUseFree) as? Bool ?? true
        libreTranslateBaseURL = defaults.string(forKey: Keys.libreTranslateBaseURL) ?? ProviderDefaults.libreTranslateBaseURL
        libreTranslateAPIKey = (try? keychain.read(account: Accounts.libreTranslateAPIKey)) ?? ""
    }

    private static func loadCodable<T: Decodable>(
        _ type: T.Type,
        defaults: UserDefaults,
        key: String
    ) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func persist<T: Encodable>(_ value: T, forKey key: String) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        }
    }

    private static func migrateSecret(_ migration: CredentialMigration, key: String, account: String) {
        do {
            try migration.migrateIfNeeded(userDefaultsKey: key, account: account)
        } catch {
            logger.error("Credential migration failed for \(key, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }

    private func writeKeychain(_ value: String, account: String) {
        if value.isEmpty {
            try? keychain.delete(account: account)
        } else {
            try? keychain.write(value, account: account)
        }
    }
}

import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class SettingsStore {
    static let shared = SettingsStore()

    /// Bundle-scoped service identifier used for Keychain entries.
    /// Matches `CFBundleIdentifier` in `scripts/package_app.sh`.
    static let keychainService = "app.lookerlab.translator"

    // MARK: Source picker (Phase 3e)

    var translationSource: TranslationSource {
        didSet {
            guard translationSource != oldValue else { return }
            defaults.set(translationSource.rawValue, forKey: Keys.translationSource)
        }
    }

    var directProvider: DirectProviderKind {
        didSet {
            guard directProvider != oldValue else { return }
            defaults.set(directProvider.rawValue, forKey: Keys.directProvider)
        }
    }

    // MARK: Custom backend (legacy `endpoint` + `apiKey`)

    var endpoint: String {
        didSet {
            guard endpoint != oldValue else { return }
            defaults.set(endpoint, forKey: Keys.endpoint)
        }
    }

    var apiKey: String {
        didSet {
            guard apiKey != oldValue else { return }
            writeKeychain(apiKey, account: Accounts.apiKey)
        }
    }

    // MARK: 1st-party backend (separate slot so user can switch without re-entering)

    var firstPartyEndpoint: String {
        didSet {
            guard firstPartyEndpoint != oldValue else { return }
            defaults.set(firstPartyEndpoint, forKey: Keys.firstPartyEndpoint)
        }
    }

    var firstPartyToken: String {
        didSet {
            guard firstPartyToken != oldValue else { return }
            writeKeychain(firstPartyToken, account: Accounts.firstPartyToken)
        }
    }

    // MARK: SaaS cloud auth (M2.1)

    /// How the 1st-party backend authenticates: a static issued token
    /// (self-host) or a refreshable Supabase email-OTP session (cloud).
    var backendAuthMode: BackendAuthMode {
        didSet {
            guard backendAuthMode != oldValue else { return }
            defaults.set(backendAuthMode.rawValue, forKey: Keys.backendAuthMode)
        }
    }

    /// v0.9.2 — Supabase project URL + anon key + auth-config /
    /// session-store / translate-endpoint / device-identity helpers
    /// extracted to `SaaSConfig`. Reach them via `settings.saaSConfig`.
    let saaSConfig: SaaSConfig

    // MARK: Direct providers — Gemini

    var geminiAPIKey: String {
        didSet {
            guard geminiAPIKey != oldValue else { return }
            writeKeychain(geminiAPIKey, account: Accounts.geminiAPIKey)
        }
    }

    var geminiModel: String {
        didSet {
            guard geminiModel != oldValue else { return }
            defaults.set(geminiModel, forKey: Keys.geminiModel)
        }
    }

    // MARK: Direct providers — Ollama

    var ollamaBaseURL: String {
        didSet {
            guard ollamaBaseURL != oldValue else { return }
            defaults.set(ollamaBaseURL, forKey: Keys.ollamaBaseURL)
        }
    }

    var ollamaModel: String {
        didSet {
            guard ollamaModel != oldValue else { return }
            defaults.set(ollamaModel, forKey: Keys.ollamaModel)
        }
    }

    // MARK: Direct providers — Google Translate

    var googleTranslateAPIKey: String {
        didSet {
            guard googleTranslateAPIKey != oldValue else { return }
            writeKeychain(googleTranslateAPIKey, account: Accounts.googleTranslateAPIKey)
        }
    }

    // MARK: Direct providers — OpenAI-compatible

    var openAICompatBaseURL: String {
        didSet {
            guard openAICompatBaseURL != oldValue else { return }
            defaults.set(openAICompatBaseURL, forKey: Keys.openAICompatBaseURL)
        }
    }

    var openAICompatAPIKey: String {
        didSet {
            guard openAICompatAPIKey != oldValue else { return }
            writeKeychain(openAICompatAPIKey, account: Accounts.openAICompatAPIKey)
        }
    }

    var openAICompatModel: String {
        didSet {
            guard openAICompatModel != oldValue else { return }
            defaults.set(openAICompatModel, forKey: Keys.openAICompatModel)
        }
    }

    // MARK: Shared / advanced

    var glossary: String {
        didSet {
            guard glossary != oldValue else { return }
            writeKeychain(glossary, account: Accounts.glossary)
        }
    }

    /// v0.10.0 — typed glossary entries (Theme B Lite). Stored in
    /// Keychain under a NEW account name; the legacy `glossary: String`
    /// blob above is UNTOUCHED so v0.9.x users who never open the new
    /// editor keep their data byte-identical. Both feed into
    /// PromptBuilder in P6 (structured rules first, then legacy blob).
    var glossaryEntries: [GlossaryEntry] {
        didSet {
            guard glossaryEntries != oldValue else { return }
            if let data = try? JSONEncoder().encode(glossaryEntries),
               let json = String(data: data, encoding: .utf8) {
                writeKeychain(json, account: Accounts.glossaryEntries)
            }
        }
    }

    var focusGuardEnabled: Bool {
        didSet {
            guard focusGuardEnabled != oldValue else { return }
            defaults.set(focusGuardEnabled, forKey: Keys.focusGuardEnabled)
        }
    }

    var firstRunCompleted: Bool {
        didSet {
            guard firstRunCompleted != oldValue else { return }
            defaults.set(firstRunCompleted, forKey: Keys.firstRunCompleted)
        }
    }

    // MARK: Multi-language (v0.3 / Phase 8)

    /// User's primary readable language (BCP47). Inbound translations
    /// always target this; outbound translations use this as the source.
    var primaryLanguage: String {
        didSet {
            guard primaryLanguage != oldValue else { return }
            defaults.set(primaryLanguage, forKey: Keys.primaryLanguage)
        }
    }

    /// Hotkey for inbound translation (selection → primary language).
    var inboundBinding: InboundBinding {
        didSet {
            guard inboundBinding != oldValue else { return }
            persist(inboundBinding, forKey: Keys.inboundBinding)
        }
    }

    /// Outbound translation bindings. Each entry = (target language +
    /// register + hotkey + optional custom style instruction). Defaults
    /// reproduce v0.2 keigo + casual hotkeys for back-compat.
    var outboundBindings: [OutboundBinding] {
        didSet {
            guard outboundBindings != oldValue else { return }
            persist(outboundBindings, forKey: Keys.outboundBindings)
        }
    }

    /// Contextual-rewrite bindings (v0.7). Each entry = (tone + optional
    /// custom instruction + hotkey). Defaults to empty — rewrite needs an
    /// LLM provider the user may not have configured, so nothing is seeded.
    var rewriteBindings: [RewriteBinding] {
        didSet {
            guard rewriteBindings != oldValue else { return }
            persist(rewriteBindings, forKey: Keys.rewriteBindings)
        }
    }

    /// Single global hotkey that opens the tone picker (v0.8). `nil` means
    /// the picker is disabled — the user explicitly assigns it in Settings.
    var pickerHotkey: HotkeyConfig? {
        didSet {
            guard pickerHotkey != oldValue else { return }
            if let pickerHotkey {
                persist(pickerHotkey, forKey: Keys.pickerHotkey)
            } else {
                defaults.removeObject(forKey: Keys.pickerHotkey)
            }
        }
    }

    /// v0.9.0 — single global hotkey that triggers the OCR-from-screen
    /// translate flow. `nil` means OCR capture is disabled. Persistence
    /// + invariant pattern identical to `pickerHotkey`.
    var captureHotkey: HotkeyConfig? {
        didSet {
            guard captureHotkey != oldValue else { return }
            if let captureHotkey {
                persist(captureHotkey, forKey: Keys.captureHotkey)
            } else {
                defaults.removeObject(forKey: Keys.captureHotkey)
            }
        }
    }

    /// v0.9.0 — last app version whose What's-New window was shown.
    /// Empty string = never shown. AppDelegate compares against
    /// `CFBundleShortVersionString` on launch and pops the window once
    /// per fresh minor/major release.
    var lastShownWhatsNewVersion: String {
        didSet {
            guard lastShownWhatsNewVersion != oldValue else { return }
            defaults.set(lastShownWhatsNewVersion, forKey: Keys.lastShownWhatsNewVersion)
        }
    }

    /// Opt-in to expressive rewrite tones (v0.8.2 — "Chửi thề" / casual
    /// raw). Default OFF: only neutral tones (Polite, Professional, …)
    /// show up in the picker + binding dropdowns until enabled. The
    /// Settings UI guards the OFF→ON transition with a confirmation
    /// dialog, so toggling this property on by itself implies consent.
    var expressiveTonesEnabled: Bool {
        didSet {
            guard expressiveTonesEnabled != oldValue else { return }
            defaults.set(expressiveTonesEnabled, forKey: Keys.expressiveTonesEnabled)
        }
    }

    /// v0.8.5 — generate 3 draft rewrites per invocation and let the
    /// user page through them in the preview HUD before sending.
    /// Default OFF: existing users keep the single-draft, faster path.
    /// Costs ~1.5–2× tokens per rewrite when ON (single round-trip,
    /// not three separate calls).
    var multiVariantRewriteEnabled: Bool {
        didSet {
            guard multiVariantRewriteEnabled != oldValue else { return }
            defaults.set(multiVariantRewriteEnabled, forKey: Keys.multiVariantRewriteEnabled)
        }
    }

    /// v0.10.0 — Vietnamese social-register card. `nil` = disabled
    /// (default; v0.9.x behaviour byte-identical for existing users).
    /// When set, every rewrite + outbound translate composes the card
    /// into the prompt via `RegisterCard.prompted(prefix:)`. Persisted
    /// as JSON in UserDefaults so the structured Codable shape survives
    /// adding new axes in v0.10.x without migration churn.
    var registerCard: RegisterCard? {
        didSet {
            guard registerCard != oldValue else { return }
            if let registerCard,
               let data = try? JSONEncoder().encode(registerCard) {
                defaults.set(data, forKey: Keys.registerCard)
            } else {
                defaults.removeObject(forKey: Keys.registerCard)
            }
        }
    }

    // MARK: Direct providers — DeepL (v0.3)

    var deeplAPIKey: String {
        didSet {
            guard deeplAPIKey != oldValue else { return }
            writeKeychain(deeplAPIKey, account: Accounts.deeplAPIKey)
        }
    }

    /// `true` = use Free endpoint (api-free.deepl.com), `false` = Pro
    /// (api.deepl.com). Free is the common case so default true.
    var deeplUseFree: Bool {
        didSet {
            guard deeplUseFree != oldValue else { return }
            defaults.set(deeplUseFree, forKey: Keys.deeplUseFree)
        }
    }

    // MARK: Direct providers — LibreTranslate (v0.3)

    var libreTranslateBaseURL: String {
        didSet {
            guard libreTranslateBaseURL != oldValue else { return }
            defaults.set(libreTranslateBaseURL, forKey: Keys.libreTranslateBaseURL)
        }
    }

    var libreTranslateAPIKey: String {
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
        // SaaS cloud auth (M2.1)
        static let backendAuthMode = "translator.backendAuthMode"
        // (v0.9.2 — supabase URL/anonKey keys live on `SaaSConfig.Keys`)
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
        // v0.7 contextual rewrite
        static let rewriteBindings = "translator.rewriteBindings"
        // v0.8 tone picker hotkey
        static let pickerHotkey = "translator.pickerHotkey"
        static let captureHotkey = "translator.captureHotkey"
        static let lastShownWhatsNewVersion = "translator.lastShownWhatsNewVersion"
        // v0.8.2 expressive tones (Chửi thề)
        static let expressiveTonesEnabled = "translator.expressiveTonesEnabled"
        static let multiVariantRewriteEnabled = "translator.multiVariantRewriteEnabled"
        // v0.10.0 — VN social register card
        static let registerCard = "translator.registerCard"
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
        // v0.10.0 — typed glossary entries (fresh Keychain slot;
        // legacy `default-glossary` blob above stays untouched)
        static let glossaryEntries = "glossary-entries-v2"
        // (v0.9.2 — deviceID Keychain account lives on `SaaSConfig.Accounts`)
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
        // Contextual MT Cloud — both values are public by design (the anon
        // key is meant to ship in clients; RLS protects data server-side).
        // Pre-filled so cloud sign-in needs only an email + OTP code.
        static let supabaseURL = "https://dtpeinsccoltpfhufyag.supabase.co"
        static let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImR0cGVpbnNjY29sdHBmaHVmeWFnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzkyODM2MTYsImV4cCI6MjA5NDg1OTYxNn0.yhOwyfRX1tUBmro0A5DluuCl1Tig20e2cI3wYN1qO1s"
        // Dashboard origin — host of the one-click `/connect` authorize page.
        static let dashboardURL = "https://app.contextmt.dev"
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

        // SaaS cloud auth (M2.1) — supabase URL/anon key + auth-config /
        // session-store / translate-endpoint / device-identity all live
        // on `SaaSConfig` (extracted in v0.9.2).
        backendAuthMode = defaults.string(forKey: Keys.backendAuthMode)
            .flatMap(BackendAuthMode.init(rawValue:)) ?? .selfHostStaticToken
        saaSConfig = SaaSConfig(
            defaults: defaults,
            keychain: keychain,
            defaultSupabaseURL: ProviderDefaults.supabaseURL,
            defaultSupabaseAnonKey: ProviderDefaults.supabaseAnonKey
        )

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
        // v0.10.0 — typed glossary entries. Forward-compat partial
        // recovery: a future build adding a new GlossaryEntry.KindTag
        // would persist entries this build can't represent. The
        // forgiving loader drops only the unknown entries instead of
        // nuking the whole list (review H3 fix; matches define.md §6
        // R1's stated intent). Legacy blob flows untouched in parallel.
        if let json = (try? keychain.read(account: Accounts.glossaryEntries)) ?? nil,
           let data = json.data(using: .utf8) {
            glossaryEntries = GlossaryEntry.decodeArray(from: data)
        } else {
            glossaryEntries = []
        }
        focusGuardEnabled = defaults.object(forKey: Keys.focusGuardEnabled) as? Bool ?? true
        firstRunCompleted = defaults.bool(forKey: Keys.firstRunCompleted)

        // v0.3 multi-lang — back-compat defaults match v0.2 hardcoded behaviour
        primaryLanguage = defaults.string(forKey: Keys.primaryLanguage) ?? "vi"
        inboundBinding = Self.loadCodable(InboundBinding.self, defaults: defaults, key: Keys.inboundBinding)
            ?? .default
        outboundBindings = Self.loadCodable([OutboundBinding].self, defaults: defaults, key: Keys.outboundBindings)
            ?? [.defaultJapaneseFormal, .defaultJapaneseCasual]
        rewriteBindings = Self.loadCodable([RewriteBinding].self, defaults: defaults, key: Keys.rewriteBindings)
            ?? []
        pickerHotkey = Self.loadCodable(HotkeyConfig.self, defaults: defaults, key: Keys.pickerHotkey)
        captureHotkey = Self.loadCodable(HotkeyConfig.self, defaults: defaults, key: Keys.captureHotkey)
        lastShownWhatsNewVersion = defaults.string(forKey: Keys.lastShownWhatsNewVersion) ?? ""

        // v0.8.2 expressive tones — default OFF; the Settings toggle
        // shows a confirmation dialog before flipping it on.
        expressiveTonesEnabled = defaults.object(forKey: Keys.expressiveTonesEnabled) as? Bool ?? false
        // v0.8.5 — off by default so existing users keep the cheaper
        // single-draft path. Opt in via Settings → Contextual rewrite.
        multiVariantRewriteEnabled = defaults.object(forKey: Keys.multiVariantRewriteEnabled) as? Bool ?? false
        // v0.10.0 — RegisterCard load. nil-on-decode-error preserves
        // v0.9.x behaviour for users who never saved one + protects
        // against forward-shaped JSON from future v0.10.x builds.
        if let data = defaults.data(forKey: Keys.registerCard) {
            registerCard = try? JSONDecoder().decode(RegisterCard.self, from: data)
        } else {
            registerCard = nil
        }

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

    // v0.9.2 — SaaS cloud auth helpers extracted to `SaaSConfig`.
    // Access via `settings.saaSConfig.{authConfig(), makeSessionStore(),
    // translateEndpoint, deviceIdentity()}`.

    // MARK: Conflict detection

    /// Check whether `hotkey` is already used by an inbound or outbound
    /// binding. Optional `excludeID` skips a specific outbound binding so
    /// users can re-confirm an existing hotkey without spurious warnings.
    /// Returns the human-readable label of the conflicting binding when
    /// found, or `nil` when free.
    func bindingLabel(usingHotkey hotkey: HotkeyConfig, excluding excludeID: UUID? = nil) -> String? {
        if inboundBinding.hotkey == hotkey {
            return "Inbound (selection → \(LanguageCatalog.englishName(for: primaryLanguage)))"
        }
        for binding in outboundBindings where binding.id != excludeID {
            if binding.hotkey == hotkey {
                return binding.displayName
            }
        }
        for binding in rewriteBindings where binding.id != excludeID {
            if binding.hotkey == hotkey {
                return binding.displayName
            }
        }
        if let pickerHotkey, pickerHotkey == hotkey {
            return "Tone picker"
        }
        if let captureHotkey, captureHotkey == hotkey {
            return "OCR capture"
        }
        return nil
    }

    /// `true` when the active provider can perform a tone rewrite. Only
    /// direct-API LLM providers qualify — backend modes are deferred, and
    /// DeepL / Google Translate / LibreTranslate cannot rewrite at all.
    var rewriteAvailable: Bool {
        guard translationSource == .directAPI else { return false }
        return directProvider.supportsRewrite
    }
}

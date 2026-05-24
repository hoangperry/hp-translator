import Foundation

/// Resolves the active `TranslationProvider` from `SettingsStore`. Each
/// call to `make()` returns a fresh provider configured against the
/// current Settings values, so changes apply immediately on the next
/// hotkey press without recreating any owning controllers.
@MainActor
final class TranslationProviderFactory {
    private let settings: SettingsStore
    private let session: URLSession
    private let idempotencyKeyProvider: @MainActor () -> String

    init(
        settings: SettingsStore,
        session: URLSession = .shared,
        idempotencyKeyProvider: @escaping @MainActor () -> String = { UUID().uuidString }
    ) {
        self.settings = settings
        self.session = session
        self.idempotencyKeyProvider = idempotencyKeyProvider
    }

    func make() -> any TranslationProvider {
        switch settings.translationSource {
        case .directAPI:
            return makeDirectProvider()
        case .customBackend, .firstPartyBackend:
            // Both backend modes share `BackendProvider` — they only differ
            // in which endpoint/token slot Settings reads from. We achieve
            // this by passing a per-source `SettingsStore` adapter so the
            // BackendProvider sees the right pair without knowing which
            // source picked it.
            return makeBackendProvider()
        }
    }

    // MARK: - Direct dispatch

    private func makeDirectProvider() -> any TranslationProvider {
        switch settings.directProvider {
        case .gemini:
            return GeminiDirectProvider(
                config: GeminiDirectProvider.Config(
                    apiKey: settings.geminiAPIKey,
                    model: nonEmpty(settings.geminiModel) ?? SettingsStore.ProviderDefaults.geminiModel,
                    maxOutputTokens: 1024,
                    timeout: 20
                ),
                session: session
            )
        case .ollama:
            return OllamaDirectProvider(
                config: OllamaDirectProvider.Config(
                    baseURL: nonEmpty(settings.ollamaBaseURL) ?? SettingsStore.ProviderDefaults.ollamaBaseURL,
                    model: nonEmpty(settings.ollamaModel) ?? SettingsStore.ProviderDefaults.ollamaModel,
                    timeout: 45
                ),
                session: session
            )
        case .googleTranslate:
            return GoogleTranslateDirectProvider(
                config: GoogleTranslateDirectProvider.Config(
                    apiKey: settings.googleTranslateAPIKey,
                    timeout: 20
                ),
                session: session
            )
        case .openAICompatible:
            return OpenAICompatibleDirectProvider(
                config: OpenAICompatibleDirectProvider.Config(
                    baseURL: nonEmpty(settings.openAICompatBaseURL) ?? SettingsStore.ProviderDefaults.openAICompatBaseURL,
                    apiKey: settings.openAICompatAPIKey,
                    model: nonEmpty(settings.openAICompatModel) ?? SettingsStore.ProviderDefaults.openAICompatModel,
                    timeout: 20
                ),
                session: session
            )
        case .deepl:
            return DeepLDirectProvider(
                config: DeepLDirectProvider.Config(
                    apiKey: settings.deeplAPIKey,
                    useFreeEndpoint: settings.deeplUseFree,
                    timeout: 20
                ),
                session: session
            )
        case .libreTranslate:
            return LibreTranslateDirectProvider(
                config: LibreTranslateDirectProvider.Config(
                    baseURL: nonEmpty(settings.libreTranslateBaseURL) ?? SettingsStore.ProviderDefaults.libreTranslateBaseURL,
                    apiKey: settings.libreTranslateAPIKey,
                    timeout: 20
                ),
                session: session
            )
        case .geminiCLI:
            return GeminiCLIProvider(config: GeminiCLIProvider.Config(
                command: "gemini",
                model: "",
                timeout: 45
            ))
        case .codexCLI:
            return CodexCLIProvider(config: CodexCLIProvider.Config(
                command: "codex",
                model: "",
                timeout: 60,
                useOSS: false,
                localProvider: ""
            ))
        case .mock:
            return MockDirectProvider()
        }
    }

    // MARK: - Backend dispatch

    private func makeBackendProvider() -> any TranslationProvider {
        // For now both backend modes route through `BackendProvider`,
        // which already reads `settings.endpoint` + `settings.apiKey`.
        // 1st-party mode uses a separate slot to preserve user creds when
        // toggling sources; we briefly swap the active values into the
        // BackendProvider via the `BackendProviderAdapter`.
        switch settings.translationSource {
        case .firstPartyBackend:
            // SaaS cloud (M2.1): when the 1st-party backend uses Supabase
            // email-OTP auth, build a fresh SupabaseAuthService that reads
            // the latest session from the Keychain store and feed
            // BackendProvider a refreshing access-token closure.
            if settings.backendAuthMode == .saasSupabaseSession,
               let config = settings.saaSConfig.authConfig() {
                let authService = SupabaseAuthService(
                    config: config,
                    session: session,
                    store: settings.saaSConfig.makeSessionStore()
                )
                let endpoint = settings.saaSConfig.translateEndpoint
                return BackendProvider(
                    settings: settings,
                    session: session,
                    idempotencyKeyProvider: idempotencyKeyProvider,
                    endpointOverride: { endpoint },
                    accessTokenProvider: { try await authService.currentAccessToken() },
                    deviceIdentityProvider: { [weak settings] in
                        settings?.saaSConfig.deviceIdentity()
                            ?? DeviceIdentity(deviceID: "", deviceName: "Mac", osVersion: "")
                    }
                )
            }
            return BackendProvider(
                settings: settings,
                session: session,
                idempotencyKeyProvider: idempotencyKeyProvider,
                endpointOverride: { [weak settings] in settings?.firstPartyEndpoint ?? "" },
                tokenOverride: { [weak settings] in settings?.firstPartyToken ?? "" }
            )
        default:
            return BackendProvider(
                settings: settings,
                session: session,
                idempotencyKeyProvider: idempotencyKeyProvider
            )
        }
    }

    private func nonEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

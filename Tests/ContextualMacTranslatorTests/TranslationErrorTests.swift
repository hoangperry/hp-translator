import Testing
@testable import ContextualMacTranslator

@Suite("TranslationError messaging")
struct TranslationErrorTests {
    @Test("missingEndpoint guides user to Settings")
    func missingEndpointMessage() {
        let message = TranslationError.missingEndpoint.errorDescription ?? ""
        #expect(message.contains("Settings"))
    }

    @Test("backendUnreachable includes the endpoint URL")
    func backendUnreachableEchoesEndpoint() {
        let endpoint = "http://127.0.0.1:8765/translate"
        let message = TranslationError.backendUnreachable(endpoint: endpoint).errorDescription ?? ""
        #expect(message.contains(endpoint))
        #expect(message.contains("server is running") || message.contains("endpoint URL"))
    }

    @Test("401 response prompts API key check")
    func unauthorizedMessageMentionsApiKey() {
        let message = TranslationError.invalidResponse(401).errorDescription ?? ""
        #expect(message.contains("401"))
        #expect(message.contains("API key"))
    }

    @Test("403 response prompts API key check")
    func forbiddenMessageMentionsApiKey() {
        let message = TranslationError.invalidResponse(403).errorDescription ?? ""
        #expect(message.contains("403"))
        #expect(message.contains("API key"))
    }

    @Test("404 response prompts URL check")
    func notFoundMentionsTranslatePath() {
        let message = TranslationError.invalidResponse(404).errorDescription ?? ""
        #expect(message.contains("404"))
        #expect(message.contains("/translate"))
    }

    @Test("5xx response identified as backend error")
    func serverErrorIsBackendError() {
        let message = TranslationError.invalidResponse(500).errorDescription ?? ""
        #expect(message.contains("500"))
        #expect(message.lowercased().contains("backend error") || message.lowercased().contains("server"))
    }

    @Test("Other status codes still surface the code")
    func otherStatusCodeIsIncluded() {
        let message = TranslationError.invalidResponse(418).errorDescription ?? ""
        #expect(message.contains("418"))
    }

    @Test("focusChangedAfterPaste warns paste is committed")
    func focusChangedAfterPasteIsHonest() {
        let message = TranslationError.focusChangedAfterPaste.errorDescription ?? ""
        #expect(message.contains("pasted"))
    }

    @Test("insecureEndpoint explains HTTPS requirement")
    func insecureEndpointMentionsHTTPS() {
        let endpoint = "http://translator.example.com/translate"
        let message = TranslationError.insecureEndpoint(endpoint: endpoint).errorDescription ?? ""
        #expect(message.contains("HTTPS"))
        #expect(message.contains(endpoint))
    }
}

@Suite("SettingsStore default endpoint")
@MainActor
struct SettingsStoreDefaultEndpointTests {
    @Test("defaultEndpoint targets the loopback reference backend")
    func defaultEndpointIsLoopback() {
        #expect(SettingsStore.defaultEndpoint == "http://127.0.0.1:8765/translate")
    }
}

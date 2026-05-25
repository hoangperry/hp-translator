import Foundation

/// Direct call to a local Ollama instance. Privacy-first option — text
/// never leaves the user's machine.
///
/// Mirrors Python `OllamaProvider`: hits `/api/generate` with the system
/// prompt as `system` and the formatted user prompt as `prompt`,
/// streaming disabled to keep the response shape simple.
@MainActor
final class OllamaDirectProvider: TranslationProvider {
    static var providerKey: String { "ollama" }
    static var displayName: String { "Ollama (local)" }
    static var privacyClass: ProviderPrivacyClass { .local }

    struct Config: Sendable {
        var baseURL: String
        var model: String
        var timeout: TimeInterval

        static let `default` = Config(
            baseURL: "http://127.0.0.1:11434",
            model: "qwen2.5:7b-instruct",
            timeout: 45
        )
    }

    private let config: Config
    private let session: URLSession

    init(config: Config, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    var isConfigured: Bool {
        !config.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !config.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func translate(_ job: TranslationJob) async throws -> TranslationResult {
        guard isConfigured else { throw TranslationError.missingEndpoint }

        let trimmedBase = config.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        let endpoint = "\(trimmedBase)/api/generate"
        guard let url = URL(string: endpoint) else { throw TranslationError.missingEndpoint }

        var request = URLRequest(url: url, timeoutInterval: config.timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": config.model,
            "system": PromptBuilder.systemPrompt(for: job),
            "prompt": PromptBuilder.userPrompt(for: job),
            "stream": false,
            "options": [
                "temperature": PromptBuilder.temperature(for: job.style)
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, http) = try await HTTPClient.send(request, endpoint: endpoint, session: session)
        if !(200...299).contains(http.statusCode) {
            throw HTTPClient.translationError(for: http, body: data)
        }

        guard
            let object = try? JSONSerialization.jsonObject(with: data),
            let dict = object as? [String: Any],
            let response = dict["response"] as? String,
            !response.isEmpty
        else {
            throw TranslationError.missingTranslation
        }
        return TranslationResult(translation: PromptBuilder.normalize(response))
    }
}

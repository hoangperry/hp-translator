import Foundation

/// Direct call to any OpenAI-compatible `/chat/completions` endpoint —
/// LM Studio, OpenRouter, vLLM, Together, the real OpenAI API, etc.
///
/// Mirrors Python `OpenAICompatibleProvider`. Sends the system prompt as
/// `role:system` and the user prompt as `role:user` so providers that
/// honour roles (most do) treat the system block as cacheable context.
@MainActor
final class OpenAICompatibleDirectProvider: TranslationProvider {
    static var providerKey: String { "openai-compatible" }
    static var displayName: String { "OpenAI-compatible API" }

    struct Config: Sendable {
        var baseURL: String
        var apiKey: String
        var model: String
        var timeout: TimeInterval

        static let `default` = Config(
            baseURL: "https://api.openai.com/v1",
            apiKey: "",
            model: "gpt-4.1-mini",
            timeout: 20
        )
    }

    private let config: Config
    private let session: URLSession

    init(config: Config, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    var isConfigured: Bool {
        !config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !config.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !config.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func translate(_ job: TranslationJob) async throws -> TranslationResult {
        guard isConfigured else { throw TranslationError.missingEndpoint }

        let trimmedBase = config.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        let endpoint = "\(trimmedBase)/chat/completions"
        guard let url = URL(string: endpoint) else { throw TranslationError.missingEndpoint }

        var request = URLRequest(url: url, timeoutInterval: config.timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "model": config.model,
            "temperature": PromptBuilder.temperature(for: job.persona),
            "messages": [
                ["role": "system", "content": PromptBuilder.systemPrompt],
                ["role": "user", "content": PromptBuilder.userPrompt(for: job)],
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, http) = try await HTTPClient.send(request, endpoint: endpoint, session: session)
        if !(200...299).contains(http.statusCode) {
            throw HTTPClient.translationError(for: http, body: data)
        }

        let text = try Self.extractTranslation(from: data)
        return TranslationResult(translation: PromptBuilder.normalize(text))
    }

    /// Walk OpenAI-style `choices[].message.content` (or legacy
    /// `choices[].text`, or top-level `output_text`) and return the first
    /// non-empty value.
    static func extractTranslation(from data: Data) throws -> String {
        guard
            let object = try? JSONSerialization.jsonObject(with: data),
            let dict = object as? [String: Any]
        else {
            throw TranslationError.missingTranslation
        }
        if let choices = dict["choices"] as? [[String: Any]] {
            for choice in choices {
                if let message = choice["message"] as? [String: Any],
                   let content = message["content"] as? String,
                   !content.isEmpty {
                    return content
                }
                if let text = choice["text"] as? String, !text.isEmpty {
                    return text
                }
            }
        }
        if let output = dict["output_text"] as? String, !output.isEmpty {
            return output
        }
        throw TranslationError.missingTranslation
    }
}

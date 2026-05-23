import Foundation

/// Direct call to Google AI Studio's `generativelanguage` API. Mirrors
/// the Python `GeminiProvider` so output quality is identical whether
/// the user routes through the backend or hits Google directly.
@MainActor
final class GeminiDirectProvider: TranslationProvider {
    static var providerKey: String { "gemini" }
    static var displayName: String { "Gemini (Google AI Studio)" }

    struct Config: Sendable {
        var apiKey: String
        var model: String
        var maxOutputTokens: Int
        var timeout: TimeInterval

        static let `default` = Config(
            apiKey: "",
            model: "gemini-2.5-flash",
            maxOutputTokens: 1024,
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
            && !config.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func translate(_ job: TranslationJob) async throws -> TranslationResult {
        guard isConfigured else { throw TranslationError.missingEndpoint }

        let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/\(config.model):generateContent"
        guard let url = URL(string: endpoint) else { throw TranslationError.missingEndpoint }

        var request = URLRequest(url: url, timeoutInterval: config.timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.apiKey, forHTTPHeaderField: "x-goog-api-key")

        var body: [String: Any] = [
            "systemInstruction": [
                "parts": [["text": PromptBuilder.systemPrompt(for: job)]]
            ],
            "contents": [
                [
                    "role": "user",
                    "parts": [["text": PromptBuilder.userPrompt(for: job)]],
                ]
            ],
            "generationConfig": [
                "temperature": PromptBuilder.temperature(for: job.style),
                "maxOutputTokens": config.maxOutputTokens,
            ],
        ]
        // v0.8.2: when the workflow signals an expressive rewrite tone
        // (e.g. "Chửi thề"), relax Gemini's safety thresholds so the
        // model doesn't refuse profanity-flavoured casual Vietnamese.
        // Google explicitly documents BLOCK_NONE for creative-writing
        // use cases. Strict default for every other request remains.
        if job.style.allowsExpressiveContent {
            body["safetySettings"] = Self.permissiveSafetySettings
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, http) = try await HTTPClient.send(request, endpoint: endpoint, session: session)
        if !(200...299).contains(http.statusCode) {
            throw HTTPClient.translationError(for: http, body: data)
        }

        let translation = try Self.extractTranslation(from: data)
        return TranslationResult(translation: PromptBuilder.normalize(translation))
    }

    /// Gemini `safetySettings` block used when
    /// `style.allowsExpressiveContent` is true. The four adjustable
    /// categories are explicitly set to `BLOCK_NONE`; the non-adjustable
    /// safety filters (CSAM, election integrity) remain enforced.
    nonisolated static let permissiveSafetySettings: [[String: String]] = [
        ["category": "HARM_CATEGORY_HARASSMENT",        "threshold": "BLOCK_NONE"],
        ["category": "HARM_CATEGORY_HATE_SPEECH",       "threshold": "BLOCK_NONE"],
        ["category": "HARM_CATEGORY_SEXUALLY_EXPLICIT", "threshold": "BLOCK_NONE"],
        ["category": "HARM_CATEGORY_DANGEROUS_CONTENT", "threshold": "BLOCK_NONE"],
    ]

    /// Walk Gemini's `candidates[*].content.parts[*].text` shape and
    /// return the first non-empty concatenation. Throws
    /// `.missingTranslation` when the LLM returned an empty payload (rare
    /// but possible — safety filter trips, etc.).
    static func extractTranslation(from data: Data) throws -> String {
        guard
            let object = try? JSONSerialization.jsonObject(with: data),
            let dict = object as? [String: Any],
            let candidates = dict["candidates"] as? [[String: Any]]
        else {
            throw TranslationError.missingTranslation
        }
        for candidate in candidates {
            if let content = candidate["content"] as? [String: Any],
               let parts = content["parts"] as? [[String: Any]] {
                let combined = parts
                    .compactMap { $0["text"] as? String }
                    .joined()
                if !combined.isEmpty {
                    return combined
                }
            }
        }
        throw TranslationError.missingTranslation
    }
}

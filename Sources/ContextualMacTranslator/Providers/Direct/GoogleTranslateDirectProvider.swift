import Foundation

/// Direct call to Google Cloud Translate Basic v2.
///
/// Mirrors Python `GoogleTranslateProvider`. NMT-only — no system prompt,
/// no glossary application; the persona/style instructions are ignored
/// because Translate Basic does not consume them. Use this provider when
/// the user prefers cheap MT over an LLM round-trip.
@MainActor
final class GoogleTranslateDirectProvider: TranslationProvider {
    static var providerKey: String { "google-translate" }
    static var displayName: String { "Google Translate Basic" }

    struct Config: Sendable {
        var apiKey: String
        var timeout: TimeInterval

        static let `default` = Config(apiKey: "", timeout: 20)
    }

    private let config: Config
    private let session: URLSession

    init(config: Config, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    var isConfigured: Bool {
        !config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func translate(_ job: TranslationJob) async throws -> TranslationResult {
        guard isConfigured else { throw TranslationError.missingEndpoint }

        var components = URLComponents(string: "https://translation.googleapis.com/language/translate/v2")!
        components.queryItems = [URLQueryItem(name: "key", value: config.apiKey)]
        guard let url = components.url else { throw TranslationError.missingEndpoint }
        let endpoint = url.absoluteString

        var request = URLRequest(url: url, timeoutInterval: config.timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "q": job.text,
            "target": job.targetLanguage,
            "format": "text",
            "model": "nmt",
        ]
        if !job.sourceLanguage.isEmpty && job.sourceLanguage.lowercased() != "auto" {
            body["source"] = job.sourceLanguage
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, http) = try await HTTPClient.send(request, endpoint: endpoint, session: session)
        if !(200...299).contains(http.statusCode) {
            throw HTTPClient.translationError(for: http, body: data)
        }

        guard
            let object = try? JSONSerialization.jsonObject(with: data),
            let dict = object as? [String: Any],
            let dataField = dict["data"] as? [String: Any],
            let translations = dataField["translations"] as? [[String: Any]]
        else {
            throw TranslationError.missingTranslation
        }
        for translation in translations {
            if let text = translation["translatedText"] as? String, !text.isEmpty {
                // Translate Basic returns HTML-escaped output even when format=text;
                // unescape so emojis and quotes round-trip cleanly.
                let unescaped = Self.unescapeHTML(text)
                return TranslationResult(translation: PromptBuilder.normalize(unescaped))
            }
        }
        throw TranslationError.missingTranslation
    }

    /// Cheap subset of `html.unescape` for the entities Translate Basic
    /// actually returns (`&amp;`, `&#39;`, etc.). Avoids pulling in
    /// WebKit just to decode 5 named entities.
    static func unescapeHTML(_ value: String) -> String {
        var result = value
        let mapping: [(String, String)] = [
            ("&amp;", "&"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&quot;", "\""),
            ("&#39;", "'"),
            ("&apos;", "'"),
        ]
        for (entity, replacement) in mapping {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }
        return result
    }
}

import Foundation

/// Direct call to a LibreTranslate instance — open-source MT, can be
/// self-hosted via Docker (`libretranslate/libretranslate`) for unlimited
/// free private use, or accessed via the community instance at
/// `libretranslate.com` (rate-limited, optional API key).
///
/// LibreTranslate is plain NMT — it does NOT honour `formality` /
/// register parameters. The register hint in `style` is ignored; the
/// LLM-style prompt construction does not apply here. Best for users who
/// want a fully open-source pipeline.
@MainActor
final class LibreTranslateDirectProvider: TranslationProvider {
    static var providerKey: String { "libretranslate" }
    static var displayName: String { "LibreTranslate" }

    struct Config: Sendable {
        var baseURL: String
        var apiKey: String
        var timeout: TimeInterval

        static let `default` = Config(
            baseURL: "https://libretranslate.com",
            apiKey: "",
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
        !config.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func translate(_ job: TranslationJob) async throws -> TranslationResult {
        guard isConfigured else { throw TranslationError.missingEndpoint }

        let trimmedBase = config.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        let endpoint = "\(trimmedBase)/translate"
        guard let url = URL(string: endpoint) else { throw TranslationError.missingEndpoint }

        var request = URLRequest(url: url, timeoutInterval: config.timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "q": job.text,
            "source": Self.libreCode(for: job.sourceLanguage),
            "target": Self.libreCode(for: job.targetLanguage),
            "format": "text",
        ]
        if !config.apiKey.isEmpty {
            body["api_key"] = config.apiKey
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, http) = try await HTTPClient.send(request, endpoint: endpoint, session: session)
        if !(200...299).contains(http.statusCode) {
            throw HTTPClient.translationError(for: http, body: data)
        }

        guard
            let object = try? JSONSerialization.jsonObject(with: data),
            let dict = object as? [String: Any],
            let text = dict["translatedText"] as? String,
            !text.isEmpty
        else {
            throw TranslationError.missingTranslation
        }
        return TranslationResult(translation: PromptBuilder.normalize(text))
    }

    /// LibreTranslate uses lowercase BCP47-ish codes; "auto" for source
    /// language detection. Maps a few common extras.
    static func libreCode(for bcp47: String) -> String {
        let lower = bcp47.lowercased()
        if lower == "auto" || lower.isEmpty {
            return "auto"
        }
        switch lower {
        case "zh-cn", "zh":
            return "zh"
        case "zh-tw":
            // LibreTranslate has zh_TW but most instances only ship zh.
            return "zt"
        default:
            return String(lower.split(separator: "-").first ?? Substring(lower))
        }
    }
}

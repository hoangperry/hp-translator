import Foundation

/// Direct call to DeepL Free / Pro `/v2/translate` endpoint. DeepL has
/// some of the highest NMT quality available for European + East Asian
/// languages and offers a generous Free tier (500K chars/month, no card).
///
/// Personas map to DeepL's `formality` parameter when the target language
/// supports it (DE/FR/IT/ES/NL/PL/PT-BR/PT-PT/JA/RU). For other targets
/// the parameter is silently ignored by DeepL.
@MainActor
final class DeepLDirectProvider: TranslationProvider {
    static var providerKey: String { "deepl" }
    static var displayName: String { "DeepL" }
    static var privacyClass: ProviderPrivacyClass { .cloud }

    struct Config: Sendable {
        var apiKey: String
        var useFreeEndpoint: Bool   // api-free.deepl.com vs api.deepl.com
        var timeout: TimeInterval

        static let `default` = Config(
            apiKey: "",
            useFreeEndpoint: true,
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
    }

    func translate(_ job: TranslationJob) async throws -> TranslationResult {
        guard isConfigured else { throw TranslationError.missingEndpoint }

        let host = config.useFreeEndpoint ? "https://api-free.deepl.com" : "https://api.deepl.com"
        let endpoint = "\(host)/v2/translate"
        guard let url = URL(string: endpoint) else { throw TranslationError.missingEndpoint }

        var request = URLRequest(url: url, timeoutInterval: config.timeout)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("DeepL-Auth-Key \(config.apiKey)", forHTTPHeaderField: "Authorization")

        // DeepL uses form-encoded body and uppercase BCP47-ish language codes
        // (e.g. "JA", "EN", "ZH"). Normalize a few common BCP47 → DeepL.
        var formItems: [(String, String)] = [
            ("text", job.text),
            ("target_lang", Self.deeplCode(for: job.targetLanguage, target: true)),
        ]
        if !job.sourceLanguage.isEmpty,
           job.sourceLanguage.lowercased() != "auto" {
            formItems.append(("source_lang", Self.deeplCode(for: job.sourceLanguage, target: false)))
        }
        if let formality = Self.formality(for: job.style.register) {
            formItems.append(("formality", formality))
        }
        request.httpBody = Self.formEncoded(formItems).data(using: .utf8)

        let (data, http) = try await HTTPClient.send(request, endpoint: endpoint, session: session)
        if !(200...299).contains(http.statusCode) {
            throw HTTPClient.translationError(for: http, body: data)
        }

        guard
            let object = try? JSONSerialization.jsonObject(with: data),
            let dict = object as? [String: Any],
            let translations = dict["translations"] as? [[String: Any]],
            let first = translations.first?["text"] as? String,
            !first.isEmpty
        else {
            throw TranslationError.missingTranslation
        }
        return TranslationResult(translation: PromptBuilder.normalize(first))
    }

    /// Map BCP47 codes (lowercase, with optional region) to DeepL codes
    /// (uppercase, region-tagged for some languages like EN-US/EN-GB).
    /// `target=true` means we're sending it as `target_lang`, where DeepL
    /// requires region for English/Portuguese.
    static func deeplCode(for bcp47: String, target: Bool) -> String {
        let normalized = bcp47.uppercased()
        switch normalized {
        case "EN":
            return target ? "EN-US" : "EN"
        case "PT":
            return target ? "PT-PT" : "PT"
        case "ZH-CN":
            return "ZH"
        case "ZH-TW":
            // DeepL only supports ZH (PRC) at present; pass ZH and warn via doc.
            return "ZH"
        default:
            // Strip region for languages DeepL doesn't expect it on.
            return String(normalized.split(separator: "-").first ?? Substring(normalized))
        }
    }

    static func formality(for register: Register) -> String? {
        switch register {
        case .formal: return "more"
        case .casual: return "less"
        case .neutral: return nil
        }
    }

    /// Minimal form-encoder. DeepL accepts repeated `text=` for batch but
    /// we only ever send one entry per request.
    static func formEncoded(_ items: [(String, String)]) -> String {
        items.map { key, value in
            let v = value.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? value
            return "\(key)=\(v)"
        }.joined(separator: "&")
    }
}

private extension CharacterSet {
    /// URL-form-encoded value safe set (more restrictive than urlQueryAllowed).
    static let urlQueryValueAllowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()
}

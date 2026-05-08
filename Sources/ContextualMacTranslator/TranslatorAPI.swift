import Foundation

@MainActor
final class TranslatorAPI {
    private let settings: SettingsStore
    private let session: URLSession

    init(settings: SettingsStore, session: URLSession = .shared) {
        self.settings = settings
        self.session = session
    }

    var isConfigured: Bool {
        !settings.endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func translate(_ job: TranslationJob) async throws -> TranslationResult {
        let endpoint = settings.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !endpoint.isEmpty, let url = URL(string: endpoint) else {
            throw TranslationError.missingEndpoint
        }
        guard EndpointPolicy.allows(url) else {
            throw TranslationError.insecureEndpoint(endpoint: endpoint)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !settings.apiKey.isEmpty {
            request.setValue("Bearer \(settings.apiKey)", forHTTPHeaderField: "Authorization")
        }

        let body = TranslationRequestBody(
            text: job.text,
            direction: job.direction.rawValue,
            sourceLanguage: job.sourceLanguage,
            targetLanguage: job.targetLanguage,
            persona: job.persona.rawValue,
            styleInstruction: job.persona.styleInstruction,
            glossary: job.glossary
        )
        request.httpBody = try JSONEncoder().encode(body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            // Surface connect/DNS/timeout failures as a single actionable
            // error instead of leaking the raw localized URLError, which
            // varies by macOS version and is often unhelpful for end users.
            switch urlError.code {
            case .cannotConnectToHost,
                 .cannotFindHost,
                 .networkConnectionLost,
                 .notConnectedToInternet,
                 .timedOut,
                 .dnsLookupFailed,
                 .secureConnectionFailed,
                 .resourceUnavailable:
                throw TranslationError.backendUnreachable(endpoint: endpoint)
            default:
                throw urlError
            }
        }

        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            throw TranslationError.invalidResponse(httpResponse.statusCode)
        }

        if let decoded = try? JSONDecoder().decode(TranslationResult.self, from: data) {
            return decoded
        }
        if let decoded = try? JSONDecoder().decode(FlexibleTranslationResponse.self, from: data),
           let translation = decoded.translationText {
            return TranslationResult(translation: translation)
        }
        throw TranslationError.missingTranslation
    }
}

enum EndpointPolicy {
    static func allows(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else {
            return false
        }
        if scheme == "https" {
            return true
        }
        guard scheme == "http" else {
            return false
        }
        return isLoopbackHost(url.host)
    }

    static func warning(for endpoint: String) -> String? {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed) else {
            return nil
        }
        return allows(url) ? nil : "Remote endpoints must use HTTPS."
    }

    private static func isLoopbackHost(_ host: String?) -> Bool {
        switch host?.lowercased() {
        case "localhost", "127.0.0.1", "::1":
            return true
        default:
            return false
        }
    }
}

private struct TranslationRequestBody: Encodable {
    let text: String
    let direction: String
    let sourceLanguage: String
    let targetLanguage: String
    let persona: String
    let styleInstruction: String
    let glossary: String
}

private struct FlexibleTranslationResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String?
        }

        let text: String?
        let message: Message?
    }

    let translation: String?
    let translatedText: String?
    let outputText: String?
    let output_text: String?
    let choices: [Choice]?

    var translationText: String? {
        translation
            ?? translatedText
            ?? outputText
            ?? output_text
            ?? choices?.compactMap { $0.message?.content ?? $0.text }.first
    }
}

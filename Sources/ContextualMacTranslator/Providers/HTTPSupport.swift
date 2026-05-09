import Foundation

/// Shared HTTP utilities for every provider that talks to a remote API.
///
/// The two pain points each provider hits — wrapping `URLError` into
/// actionable `TranslationError.backendUnreachable`, and parsing RFC 7807
/// problem responses — live here so direct-API providers and the backend
/// provider stay in sync.
enum HTTPClient {
    /// Send `request` and return the raw `(Data, HTTPURLResponse)` pair.
    /// Maps connection-class `URLError`s to `TranslationError.backendUnreachable`
    /// using `endpoint` as the user-visible hint; other errors propagate.
    static func send(
        _ request: URLRequest,
        endpoint: String,
        session: URLSession
    ) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw TranslationError.missingTranslation
            }
            return (data, http)
        } catch let urlError as URLError {
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
    }

    /// Map a non-2xx response to the most specific `TranslationError`. Prefers
    /// RFC 7807 `detail`/`title` from the body; falls back to status-code
    /// mapping in `TranslationError.invalidResponse`.
    static func translationError(for response: HTTPURLResponse, body: Data) -> TranslationError {
        let status = response.statusCode
        let problem = ProblemDetailsParser.parse(body)

        if status == 429 {
            let retryAfter = retryAfterSeconds(from: response)
            return .rateLimited(retryAfter: retryAfter, detail: problem?.detail)
        }
        if let problem {
            return .serverProblem(status: status, title: problem.title, detail: problem.detail)
        }
        return .invalidResponse(status)
    }

    private static func retryAfterSeconds(from response: HTTPURLResponse) -> Int {
        if let header = response.value(forHTTPHeaderField: "Retry-After"),
           let seconds = Int(header.trimmingCharacters(in: .whitespaces)) {
            return max(1, seconds)
        }
        return 1
    }
}

/// Minimal RFC 7807 decoder. Only fields we actually surface in the UI
/// are kept; we deliberately avoid `JSONDecoder` typed-decode here so a
/// malformed body cannot crash error handling.
struct ProblemDetails {
    let type: String?
    let title: String?
    let status: Int?
    let detail: String?
    let instance: String?
}

enum ProblemDetailsParser {
    static func parse(_ data: Data) -> ProblemDetails? {
        guard !data.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: data),
              let dict = object as? [String: Any]
        else {
            return nil
        }
        // Accept either "detail" (RFC 7807) or "error" (legacy alias).
        let detail = (dict["detail"] as? String) ?? (dict["error"] as? String)
        let title = dict["title"] as? String
        guard detail != nil || title != nil else {
            return nil
        }
        return ProblemDetails(
            type: dict["type"] as? String,
            title: title,
            status: dict["status"] as? Int,
            detail: detail,
            instance: dict["instance"] as? String
        )
    }
}

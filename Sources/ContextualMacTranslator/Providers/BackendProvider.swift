import Foundation

/// Translation provider that routes requests through an HTTP backend
/// (the user-managed `translator-server` or a 1st-party hosted instance).
///
/// Renamed from the original `TranslatorAPI` and now conforms to
/// `TranslationProvider`. Behaviour is unchanged from the v2 adoption
/// added in Phase 2.5: per-request `Idempotency-Key`, RFC 7807 error
/// parsing, `EndpointPolicy` HTTPS gate.
@MainActor
final class BackendProvider: TranslationProvider, StreamingTranslationProvider {
    static var providerKey: String { "backend" }
    static var displayName: String { "Translator backend" }
    // BackendProvider is the proxy to a self-hosted translator-server
    // or the Supabase Edge Function — user trust depends on who runs
    // the host. Marked .hosted to distinguish from .cloud (3rd-party
    // API) and .local (on-device).
    static var privacyClass: ProviderPrivacyClass { .hosted }

    private let settings: SettingsStore
    private let session: URLSession
    private let idempotencyKeyProvider: @MainActor () -> String
    private let endpointOverride: (@MainActor () -> String)?
    private let tokenOverride: (@MainActor () -> String)?
    private let accessTokenProvider: (@Sendable () async throws -> String?)?
    private let deviceIdentityProvider: (@MainActor () -> DeviceIdentity)?

    /// Default initialiser routes against `settings.endpoint` + `settings.apiKey`
    /// — i.e. the "Custom backend" source.
    ///
    /// `endpointOverride` and `tokenOverride` let the 1st-party source feed
    /// in a separate slot so users can switch between custom and 1st-party
    /// modes without re-entering credentials.
    ///
    /// `accessTokenProvider` is the SaaS seam: when set, it supplies a
    /// freshly-refreshed bearer token per request (e.g. wrapping
    /// `SupabaseAuthService.currentAccessToken()`). It takes precedence over
    /// the static `tokenOverride` / `settings.apiKey`. Keeping it a closure
    /// keeps `BackendProvider` decoupled from the auth implementation.
    ///
    /// `deviceIdentityProvider` is the M2.1-c seam: when set, every request
    /// carries `X-Device-*` headers so the SaaS backend can register the
    /// device and enforce the plan device cap. Unset for self-host.
    init(
        settings: SettingsStore,
        session: URLSession = .shared,
        idempotencyKeyProvider: @escaping @MainActor () -> String = { UUID().uuidString },
        endpointOverride: (@MainActor () -> String)? = nil,
        tokenOverride: (@MainActor () -> String)? = nil,
        accessTokenProvider: (@Sendable () async throws -> String?)? = nil,
        deviceIdentityProvider: (@MainActor () -> DeviceIdentity)? = nil
    ) {
        self.settings = settings
        self.session = session
        self.idempotencyKeyProvider = idempotencyKeyProvider
        self.endpointOverride = endpointOverride
        self.tokenOverride = tokenOverride
        self.accessTokenProvider = accessTokenProvider
        self.deviceIdentityProvider = deviceIdentityProvider
    }

    /// Apply SaaS device-identity headers when the M2.1-c seam is wired.
    private func applyDeviceHeaders(to request: inout URLRequest) {
        guard let deviceIdentityProvider else { return }
        for (field, value) in deviceIdentityProvider().requestHeaders {
            request.setValue(value, forHTTPHeaderField: field)
        }
    }

    private var resolvedEndpoint: String {
        if let endpointOverride {
            return endpointOverride()
        }
        return settings.endpoint
    }

    /// Resolve the bearer token for this request. SaaS mode supplies a
    /// refreshable token via `accessTokenProvider`; self-host mode uses the
    /// static `tokenOverride` / `settings.apiKey`. A throw here aborts the
    /// translation — correct, since no auth means no call.
    private func resolveToken() async throws -> String {
        if let accessTokenProvider {
            return (try await accessTokenProvider()) ?? ""
        }
        if let tokenOverride {
            return tokenOverride()
        }
        return settings.apiKey
    }

    var isConfigured: Bool {
        !resolvedEndpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func translate(_ job: TranslationJob) async throws -> TranslationResult {
        let endpoint = resolvedEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !endpoint.isEmpty, let url = URL(string: endpoint) else {
            throw TranslationError.missingEndpoint
        }
        guard EndpointPolicy.allows(url) else {
            throw TranslationError.insecureEndpoint(endpoint: endpoint)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // v2: Idempotency-Key per hotkey-press protects against double-paste
        // when the network glitches mid-flight. Server cache TTL ~5min.
        request.setValue(idempotencyKeyProvider(), forHTTPHeaderField: "Idempotency-Key")
        let token = try await resolveToken()
        if !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        applyDeviceHeaders(to: &request)

        let body = BackendRequestBody(
            text: job.text,
            direction: job.direction.rawValue,
            sourceLanguage: job.sourceLanguage,
            targetLanguage: job.targetLanguage,
            persona: job.style.rawValue,
            styleInstruction: job.style.styleInstruction,
            glossary: job.glossary
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, httpResponse) = try await HTTPClient.send(request, endpoint: endpoint, session: session)
        if !(200...299).contains(httpResponse.statusCode) {
            throw HTTPClient.translationError(for: httpResponse, body: data)
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

    // MARK: - Streaming

    func translateStreaming(_ job: TranslationJob) -> AsyncThrowingStream<StreamingTranslationUpdate, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { @MainActor in
                do {
                    try await self.streamSSE(for: job, into: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Build the SSE request, walk the byte stream line-by-line, and
    /// forward parsed updates to `continuation`. Throws if the request
    /// cannot start; mid-stream errors propagate via the continuation.
    private func streamSSE(
        for job: TranslationJob,
        into continuation: AsyncThrowingStream<StreamingTranslationUpdate, Error>.Continuation
    ) async throws {
        let endpoint = resolvedEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !endpoint.isEmpty, let baseURL = URL(string: endpoint) else {
            throw TranslationError.missingEndpoint
        }
        guard EndpointPolicy.allows(baseURL) else {
            throw TranslationError.insecureEndpoint(endpoint: endpoint)
        }

        // Streaming endpoint sits next to /translate; rewrite the last
        // path component so users keep configuring a single base URL.
        let streamURL = Self.streamingURL(for: baseURL)

        var request = URLRequest(url: streamURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue(idempotencyKeyProvider(), forHTTPHeaderField: "Idempotency-Key")
        let token = try await resolveToken()
        if !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        applyDeviceHeaders(to: &request)

        let body = BackendRequestBody(
            text: job.text,
            direction: job.direction.rawValue,
            sourceLanguage: job.sourceLanguage,
            targetLanguage: job.targetLanguage,
            persona: job.style.rawValue,
            styleInstruction: job.style.styleInstruction,
            glossary: job.glossary
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (bytes, response): (URLSession.AsyncBytes, URLResponse)
        do {
            (bytes, response) = try await session.bytes(for: request)
        } catch let urlError as URLError {
            switch urlError.code {
            case .cannotConnectToHost, .cannotFindHost, .networkConnectionLost,
                 .notConnectedToInternet, .timedOut, .dnsLookupFailed,
                 .secureConnectionFailed, .resourceUnavailable:
                throw TranslationError.backendUnreachable(endpoint: streamURL.absoluteString)
            default:
                throw urlError
            }
        }

        guard let http = response as? HTTPURLResponse else {
            throw TranslationError.missingTranslation
        }
        if !(200...299).contains(http.statusCode) {
            // Read the (small) error body so RFC 7807 details are surfaced.
            var bodyData = Data()
            for try await byte in bytes {
                bodyData.append(byte)
                if bodyData.count > 8 * 1024 { break }
            }
            throw HTTPClient.translationError(for: http, body: bodyData)
        }

        // Graceful fallback: the SaaS Supabase Edge Function does not
        // implement SSE on `/translate/stream` — Supabase routes the
        // sub-path to the same `translate` function which always returns
        // a single JSON `{ translation, provider, … }` body. Detect this
        // by sniffing the Content-Type and emit a single `.done(...)` so
        // upstream UX works against both the self-hosted FastAPI server
        // (real SSE) and SaaS (one-shot JSON) without per-endpoint config.
        let contentType = (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
        let isSSE = contentType.contains("text/event-stream")
        if !isSSE {
            var bodyData = Data()
            for try await byte in bytes {
                bodyData.append(byte)
                if bodyData.count > 256 * 1024 { break }   // 256KB safety cap
            }
            if let decoded = try? JSONDecoder().decode(TranslationResult.self, from: bodyData),
               !decoded.translation.isEmpty {
                continuation.yield(.done(translation: decoded.translation, provider: "backend"))
                return
            }
            if let decoded = try? JSONDecoder().decode(FlexibleTranslationResponse.self, from: bodyData),
               let translation = decoded.translationText {
                continuation.yield(.done(translation: translation, provider: "backend"))
                return
            }
            throw TranslationError.missingTranslation
        }

        for try await line in bytes.lines {
            // SSE frames are blank-line separated; the `URLSession.bytes.lines`
            // sequence already splits on `\n`, so each non-blank line
            // starting with `data:` carries one frame's payload.
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("data:") else { continue }
            let jsonText = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
            guard let data = jsonText.data(using: .utf8),
                  let frame = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }

            if let chunk = frame["chunk"] as? String {
                continuation.yield(.chunk(chunk))
            } else if let done = frame["done"] as? Bool, done {
                let translation = frame["translation"] as? String ?? ""
                let providerName = frame["provider"] as? String ?? "backend"
                continuation.yield(.done(translation: translation, provider: providerName))
                return
            } else if let errorBody = frame["error"] as? [String: Any] {
                let status = errorBody["status"] as? Int ?? 500
                let title = errorBody["title"] as? String
                let detail = (errorBody["detail"] as? String) ?? (errorBody["error"] as? String)
                throw TranslationError.serverProblem(status: status, title: title, detail: detail)
            }
        }
    }

    /// Compose the `/translate/stream` URL from the configured `/translate`
    /// endpoint. Falls back to appending `/translate/stream` if the user
    /// configured a non-standard path.
    ///
    /// `nonisolated` so the pure URL-rewriting can be unit-tested from
    /// any actor context without `await`.
    nonisolated static func streamingURL(for endpoint: URL) -> URL {
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) ?? URLComponents()
        let path = components.path
        if path.hasSuffix("/translate") {
            components.path = path + "/stream"
        } else if path.isEmpty || path == "/" {
            components.path = "/translate/stream"
        } else if path.hasSuffix("/") {
            components.path = path + "translate/stream"
        } else {
            components.path = path + "/stream"
        }
        return components.url ?? endpoint
    }
}

private struct BackendRequestBody: Encodable {
    let text: String
    let direction: String
    let sourceLanguage: String
    let targetLanguage: String
    let persona: String
    let styleInstruction: String
    let glossary: String

    // Emit each field under BOTH camelCase (legacy self-hosted FastAPI in
    // translator-server/server.py reads `sourceLanguage`, `targetLanguage`,
    // `styleInstruction`) AND snake_case (the SaaS Supabase Edge Function
    // at translator-supabase/supabase/functions/translate/index.ts validates
    // `target_language` as a hard requirement). Each server ignores the
    // unknown duplicate, so one payload works against both backends.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicKey.self)
        try container.encode(text, forKey: DynamicKey("text"))
        try container.encode(direction, forKey: DynamicKey("direction"))
        try container.encode(sourceLanguage, forKey: DynamicKey("sourceLanguage"))
        try container.encode(sourceLanguage, forKey: DynamicKey("source_language"))
        try container.encode(targetLanguage, forKey: DynamicKey("targetLanguage"))
        try container.encode(targetLanguage, forKey: DynamicKey("target_language"))
        try container.encode(persona, forKey: DynamicKey("persona"))
        try container.encode(persona, forKey: DynamicKey("persona_id"))
        try container.encode(styleInstruction, forKey: DynamicKey("styleInstruction"))
        try container.encode(styleInstruction, forKey: DynamicKey("style_instruction"))
        try container.encode(glossary, forKey: DynamicKey("glossary"))
    }

    private struct DynamicKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }

        init(_ value: String) { self.stringValue = value }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }
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

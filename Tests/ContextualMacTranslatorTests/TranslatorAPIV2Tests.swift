import Foundation
import Testing

@testable import ContextualMacTranslator

// MARK: - URLProtocol stub

/// Minimal URLProtocol that returns a programmable response for the next
/// request. Tests configure the stub via the static properties on
/// `MockURLProtocol`, then run the call against a `URLSession` whose
/// `protocolClasses` only contains this class.
final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var stub: ((URLRequest) -> (HTTPURLResponse, Data))?
    nonisolated(unsafe) static var capturedRequests: [URLRequest] = []

    static func reset() {
        stub = nil
        capturedRequests = []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.capturedRequests.append(self.request)
        guard let stub = Self.stub else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        let (response, data) = stub(self.request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor
private func makeAPI(
    endpoint: String = "http://127.0.0.1:8765/translate",
    apiKey: String = "",
    idempotencyKey: String = "fixed-test-uuid"
) -> (BackendProvider, URLSession) {
    let suiteName = "translator-tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)

    let keychain = KeychainCredentialStore(service: "translator-tests.\(UUID().uuidString)")
    let settings = SettingsStore(defaults: defaults, keychain: keychain)
    settings.endpoint = endpoint
    settings.apiKey = apiKey

    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: config)

    let api = BackendProvider(
        settings: settings,
        session: session,
        idempotencyKeyProvider: { idempotencyKey }
    )
    return (api, session)
}

private func makeJob() -> TranslationJob {
    TranslationJob(
        text: "xin chao",
        direction: .inbound,
        sourceLanguage: "vi",
        targetLanguage: "vi",
        persona: .vietnameseReader,
        glossary: ""
    )
}

private func httpResponse(status: Int, headers: [String: String] = [:]) -> HTTPURLResponse {
    HTTPURLResponse(
        url: URL(string: "http://127.0.0.1:8765/translate")!,
        statusCode: status,
        httpVersion: "HTTP/1.1",
        headerFields: headers
    )!
}

// MARK: - v2 network behaviour
// Wrapped under one serialized parent so all `MockURLProtocol`-based suites
// share a single sequential queue. Individual sub-suites stay logically
// grouped for readability.

@Suite("BackendProvider v2 network", .serialized)
@MainActor
struct BackendProviderV2NetworkSuites {

@Suite("Idempotency-Key")
@MainActor
struct BackendProviderIdempotencyTests {
    @Test("Sends Idempotency-Key header on every request")
    func sendsIdempotencyKeyHeader() async throws {
        MockURLProtocol.reset()
        MockURLProtocol.stub = { _ in
            (httpResponse(status: 200), Data(#"{"translation":"ok"}"#.utf8))
        }

        let (api, _) = makeAPI(idempotencyKey: "deterministic-key-1")
        _ = try await api.translate(makeJob())

        let captured = try #require(MockURLProtocol.capturedRequests.first)
        let key = captured.value(forHTTPHeaderField: "Idempotency-Key")
        #expect(key == "deterministic-key-1")
    }

    @Test("Each call uses a fresh key from the provider")
    func providerCalledPerRequest() async throws {
        MockURLProtocol.reset()
        MockURLProtocol.stub = { _ in
            (httpResponse(status: 200), Data(#"{"translation":"ok"}"#.utf8))
        }

        var keyIndex = 0
        let suiteName = "translator-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = SettingsStore(
            defaults: defaults,
            keychain: KeychainCredentialStore(service: "translator-tests.\(UUID().uuidString)")
        )
        settings.endpoint = "http://127.0.0.1:8765/translate"

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)

        let api = BackendProvider(
            settings: settings,
            session: session,
            idempotencyKeyProvider: {
                keyIndex += 1
                return "key-\(keyIndex)"
            }
        )

        _ = try await api.translate(makeJob())
        _ = try await api.translate(makeJob())

        let keys = MockURLProtocol.capturedRequests.compactMap {
            $0.value(forHTTPHeaderField: "Idempotency-Key")
        }
        #expect(keys == ["key-1", "key-2"])
    }
}

// MARK: - RFC 7807 parsing

@Suite("ProblemDetailsParser")
struct ProblemDetailsParserTests {
    @Test("Parses fully-populated problem body")
    func parsesFullProblem() throws {
        let json = #"""
        {
          "type": "https://example.com/errors/rate-limit",
          "title": "Too Many Requests",
          "status": 429,
          "detail": "Slow down",
          "instance": "/translate"
        }
        """#

        let problem = try #require(ProblemDetailsParser.parse(Data(json.utf8)))

        #expect(problem.type == "https://example.com/errors/rate-limit")
        #expect(problem.title == "Too Many Requests")
        #expect(problem.status == 429)
        #expect(problem.detail == "Slow down")
        #expect(problem.instance == "/translate")
    }

    @Test("Falls back to legacy `error` field for v1 servers")
    func legacyErrorAlias() throws {
        let json = #"{"error":"unauthorized"}"#

        let problem = try #require(ProblemDetailsParser.parse(Data(json.utf8)))

        #expect(problem.detail == "unauthorized")
        #expect(problem.title == nil)
    }

    @Test("Returns nil for opaque body without detail/title")
    func ignoresOpaqueBody() {
        let json = #"{"unrelated":"value"}"#

        #expect(ProblemDetailsParser.parse(Data(json.utf8)) == nil)
    }

    @Test("Returns nil for empty body")
    func ignoresEmpty() {
        #expect(ProblemDetailsParser.parse(Data()) == nil)
    }

    @Test("Returns nil for malformed JSON")
    func ignoresMalformed() {
        #expect(ProblemDetailsParser.parse(Data("not-json".utf8)) == nil)
    }
}

// MARK: - Error mapping

@Suite("Error mapping")
@MainActor
struct BackendProviderErrorMappingTests {
    @Test("429 with Retry-After surfaces rateLimited error")
    func rateLimitedWithHeader() async throws {
        MockURLProtocol.reset()
        MockURLProtocol.stub = { _ in
            let body = Data(#"{"detail":"too fast","status":429,"title":"Too Many Requests"}"#.utf8)
            return (httpResponse(status: 429, headers: ["Retry-After": "5"]), body)
        }

        let (api, _) = makeAPI()
        do {
            _ = try await api.translate(makeJob())
            Issue.record("Expected throw")
        } catch let error as TranslationError {
            switch error {
            case .rateLimited(let retryAfter, let detail):
                #expect(retryAfter == 5)
                #expect(detail == "too fast")
            default:
                Issue.record("Wrong case: \(error)")
            }
        }
    }

    @Test("429 without Retry-After defaults to 1s")
    func rateLimitedDefaultsRetryAfter() async throws {
        MockURLProtocol.reset()
        MockURLProtocol.stub = { _ in
            (httpResponse(status: 429), Data())
        }

        let (api, _) = makeAPI()
        do {
            _ = try await api.translate(makeJob())
            Issue.record("Expected throw")
        } catch let error as TranslationError {
            switch error {
            case .rateLimited(let retryAfter, _):
                #expect(retryAfter == 1)
            default:
                Issue.record("Wrong case: \(error)")
            }
        }
    }

    @Test("Server problem body surfaces detail in error")
    func serverProblemDetailEchoed() async throws {
        MockURLProtocol.reset()
        MockURLProtocol.stub = { _ in
            let body = Data(#"{"detail":"Idempotency-Key reused with different body","title":"Conflict","status":409}"#.utf8)
            return (httpResponse(status: 409), body)
        }

        let (api, _) = makeAPI()
        do {
            _ = try await api.translate(makeJob())
            Issue.record("Expected throw")
        } catch let error as TranslationError {
            switch error {
            case .serverProblem(let status, let title, let detail):
                #expect(status == 409)
                #expect(title == "Conflict")
                #expect(detail == "Idempotency-Key reused with different body")
                #expect(error.localizedDescription.contains("Idempotency-Key"))
            default:
                Issue.record("Wrong case: \(error)")
            }
        }
    }

    @Test("Opaque error body falls back to invalidResponse mapping")
    func opaqueErrorFallback() async throws {
        MockURLProtocol.reset()
        MockURLProtocol.stub = { _ in
            (httpResponse(status: 401), Data(#"{"unrelated":1}"#.utf8))
        }

        let (api, _) = makeAPI()
        do {
            _ = try await api.translate(makeJob())
            Issue.record("Expected throw")
        } catch let error as TranslationError {
            switch error {
            case .invalidResponse(let status):
                #expect(status == 401)
                #expect(error.localizedDescription.contains("API key"))
            default:
                Issue.record("Wrong case: \(error)")
            }
        }
    }

    @Test("rateLimited error message includes retry seconds")
    func rateLimitedMessage() {
        let message = TranslationError.rateLimited(retryAfter: 7, detail: "too fast").errorDescription ?? ""

        #expect(message.contains("7s"))
        #expect(message.contains("too fast"))
    }

    @Test("serverProblem prefers detail over title")
    func serverProblemPrefersDetail() {
        let withDetail = TranslationError.serverProblem(
            status: 502,
            title: "Bad Gateway",
            detail: "Upstream Gemini timed out"
        ).errorDescription ?? ""

        #expect(withDetail.contains("Upstream Gemini timed out"))
        #expect(!withDetail.contains("Bad Gateway"))
    }

    @Test("serverProblem falls back to title when detail empty")
    func serverProblemTitleFallback() {
        let titleOnly = TranslationError.serverProblem(
            status: 503,
            title: "Service Unavailable",
            detail: nil
        ).errorDescription ?? ""

        #expect(titleOnly.contains("Service Unavailable"))
    }
}

} // end BackendProviderV2NetworkSuites

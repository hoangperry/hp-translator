import Foundation
import Testing

@testable import ContextualMacTranslator

// MARK: - SSE-aware URLProtocol stub

/// URLProtocol that streams a programmable list of bytes back to the
/// caller, with optional inter-chunk delays so we exercise
/// `URLSession.bytes(for:)` line-by-line parsing realistically.
final class StreamingStubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var responder: ((URLRequest) -> StreamingStubResponse)?
    nonisolated(unsafe) static var capturedRequests: [URLRequest] = []

    static func reset() {
        responder = nil
        capturedRequests = []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.capturedRequests.append(self.request)
        guard let responder = Self.responder else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        let stubbed = responder(self.request)
        client?.urlProtocol(self, didReceive: stubbed.response, cacheStoragePolicy: .notAllowed)
        for chunk in stubbed.chunks {
            client?.urlProtocol(self, didLoad: chunk)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

struct StreamingStubResponse {
    let response: HTTPURLResponse
    let chunks: [Data]
}

private func sseSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StreamingStubProtocol.self]
    return URLSession(configuration: config)
}

private func sseFrame(_ object: [String: Any]) -> Data {
    let json = try! JSONSerialization.data(withJSONObject: object)
    var frame = Data("data: ".utf8)
    frame.append(json)
    frame.append("\n\n".data(using: .utf8)!)
    return frame
}

private func httpResponse(status: Int, contentType: String = "text/event-stream") -> HTTPURLResponse {
    HTTPURLResponse(
        url: URL(string: "http://127.0.0.1:8765/translate/stream")!,
        statusCode: status,
        httpVersion: "HTTP/1.1",
        headerFields: ["Content-Type": contentType]
    )!
}

@MainActor
private func makeBackend(endpoint: String = "http://127.0.0.1:8765/translate") -> BackendProvider {
    let suiteName = "translator-tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    let keychain = KeychainCredentialStore(service: "translator-tests.\(UUID().uuidString)")
    let settings = SettingsStore(defaults: defaults, keychain: keychain)
    settings.endpoint = endpoint
    return BackendProvider(
        settings: settings,
        session: sseSession(),
        idempotencyKeyProvider: { "fixed-stream-key" }
    )
}

private func makeJob() -> TranslationJob {
    TranslationJob(
        text: "xin chao",
        direction: .inbound,
        sourceLanguage: "auto",
        targetLanguage: "vi",
        persona: .vietnameseReader,
        glossary: ""
    )
}

@Suite("BackendProvider streaming", .serialized)
@MainActor
struct BackendStreamingTests {
    @Test("Composes /translate/stream URL from /translate endpoint")
    func streamingURLComposition() {
        let url = BackendProvider.streamingURL(for: URL(string: "https://api.example.com/translate")!)
        #expect(url.absoluteString == "https://api.example.com/translate/stream")
    }

    @Test("Composes /translate/stream when endpoint has only host")
    func streamingURLDefault() {
        let url = BackendProvider.streamingURL(for: URL(string: "https://api.example.com/")!)
        #expect(url.absoluteString == "https://api.example.com/translate/stream")
    }

    @Test("Yields chunk + done updates from SSE frames")
    func streamsChunksThenDone() async throws {
        StreamingStubProtocol.reset()
        StreamingStubProtocol.responder = { _ in
            StreamingStubResponse(
                response: httpResponse(status: 200),
                chunks: [
                    sseFrame(["chunk": "Xin"]),
                    sseFrame(["chunk": " chào"]),
                    sseFrame(["done": true, "translation": "Xin chào", "provider": "mock"]),
                ]
            )
        }
        let backend = makeBackend()

        var collected: [String] = []
        var doneTranslation: String?
        var doneProvider: String?
        for try await update in backend.translateStreaming(makeJob()) {
            switch update {
            case .chunk(let text): collected.append(text)
            case .done(let final, let provider):
                doneTranslation = final
                doneProvider = provider
            }
        }

        #expect(collected == ["Xin", " chào"])
        #expect(doneTranslation == "Xin chào")
        #expect(doneProvider == "mock")
    }

    @Test("Sends Idempotency-Key + Bearer + JSON body to /translate/stream")
    func headersAndBodyShape() async throws {
        StreamingStubProtocol.reset()
        StreamingStubProtocol.responder = { _ in
            StreamingStubResponse(
                response: httpResponse(status: 200),
                chunks: [sseFrame(["done": true, "translation": "", "provider": "mock"])]
            )
        }
        let backend = makeBackend()

        for try await _ in backend.translateStreaming(makeJob()) { /* drain */ }

        let request = try #require(StreamingStubProtocol.capturedRequests.first)
        #expect(request.url?.path == "/translate/stream")
        #expect(request.value(forHTTPHeaderField: "Idempotency-Key") == "fixed-stream-key")
        #expect(request.value(forHTTPHeaderField: "Accept") == "text/event-stream")
    }

    @Test("Mid-stream error frame surfaces as serverProblem throw")
    func midStreamErrorFrame() async throws {
        StreamingStubProtocol.reset()
        StreamingStubProtocol.responder = { _ in
            StreamingStubResponse(
                response: httpResponse(status: 200),
                chunks: [
                    sseFrame(["chunk": "partial"]),
                    sseFrame(["error": [
                        "type": "about:blank",
                        "title": "Bad Gateway",
                        "status": 502,
                        "detail": "upstream down",
                        "error": "upstream down",
                    ]]),
                ]
            )
        }
        let backend = makeBackend()

        var threw = false
        do {
            for try await _ in backend.translateStreaming(makeJob()) { /* drain */ }
        } catch let error as TranslationError {
            switch error {
            case .serverProblem(let status, let title, let detail):
                #expect(status == 502)
                #expect(title == "Bad Gateway")
                #expect(detail == "upstream down")
                threw = true
            default:
                Issue.record("Wrong case: \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
        #expect(threw)
    }

    @Test("Pre-stream HTTP failure throws translationError(for:body:)")
    func preStreamHTTPError() async throws {
        StreamingStubProtocol.reset()
        StreamingStubProtocol.responder = { _ in
            let body = Data(#"{"detail":"missing token","status":401,"title":"Unauthorized"}"#.utf8)
            return StreamingStubResponse(
                response: httpResponse(status: 401, contentType: "application/problem+json"),
                chunks: [body]
            )
        }
        let backend = makeBackend()

        do {
            for try await _ in backend.translateStreaming(makeJob()) { /* drain */ }
            Issue.record("Expected throw")
        } catch let error as TranslationError {
            switch error {
            case .serverProblem(let status, _, _):
                #expect(status == 401)
            case .invalidResponse(let status):
                #expect(status == 401)
            default:
                Issue.record("Wrong case: \(error)")
            }
        }
    }
}

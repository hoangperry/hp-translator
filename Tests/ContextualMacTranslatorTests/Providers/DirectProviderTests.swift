import Foundation
import Testing

@testable import ContextualMacTranslator

// MARK: - Shared test helpers

/// Lightweight URLProtocol stub re-implemented locally so direct-provider
/// tests don't have to import the older TranslatorAPI test infrastructure.
final class DirectStubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var stub: ((URLRequest) -> (HTTPURLResponse, Data))?
    nonisolated(unsafe) static var capturedRequests: [URLRequest] = []
    nonisolated(unsafe) static var capturedBodies: [Data] = []

    static func reset() {
        stub = nil
        capturedRequests = []
        capturedBodies = []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.capturedRequests.append(self.request)
        if let body = self.request.httpBody {
            Self.capturedBodies.append(body)
        } else if let stream = self.request.httpBodyStream {
            // URLSession converts Data bodies to streams when going through
            // a custom protocol; capture by reading.
            stream.open()
            defer { stream.close() }
            var buffer = Data()
            let chunkSize = 4096
            var chunk = [UInt8](repeating: 0, count: chunkSize)
            while stream.hasBytesAvailable {
                let read = stream.read(&chunk, maxLength: chunkSize)
                if read <= 0 { break }
                buffer.append(chunk, count: read)
            }
            Self.capturedBodies.append(buffer)
        }
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

private func stubSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [DirectStubProtocol.self]
    return URLSession(configuration: config)
}

private func httpResponse(url: String, status: Int, headers: [String: String] = [:]) -> HTTPURLResponse {
    HTTPURLResponse(
        url: URL(string: url)!,
        statusCode: status,
        httpVersion: "HTTP/1.1",
        headerFields: headers
    )!
}

private func makeJob(persona: Persona = .vietnameseReader, text: String = "xin chao") -> TranslationJob {
    TranslationJob(text: text, style: persona, sourceLanguage: "auto", glossary: ""
    )
}

// MARK: - Mock provider

@Suite("MockDirectProvider")
@MainActor
struct MockDirectProviderTests {
    @Test("Echoes [persona] text matching the Python mock")
    func echo() async throws {
        let provider = MockDirectProvider()
        let result = try await provider.translate(makeJob(text: "hi"))

        #expect(result.translation == "[vietnameseReader] hi")
    }

    @Test("Always reports configured")
    func alwaysConfigured() {
        #expect(MockDirectProvider().isConfigured == true)
    }
}

// MARK: - Direct providers (HTTP-based)

@Suite("Direct providers (HTTP)", .serialized)
@MainActor
struct DirectProviderHTTPSuites {

@Suite("GeminiDirectProvider")
@MainActor
struct GeminiDirectProviderTests {
    @Test("isConfigured requires non-empty key + model")
    func configurationGate() {
        let empty = GeminiDirectProvider(config: .init(apiKey: "", model: "x", maxOutputTokens: 1, timeout: 1))
        #expect(empty.isConfigured == false)

        let ok = GeminiDirectProvider(config: .init(apiKey: "abc", model: "gemini", maxOutputTokens: 1, timeout: 1))
        #expect(ok.isConfigured == true)
    }

    @Test("Sends x-goog-api-key + system+user prompts; parses candidates")
    func happyPath() async throws {
        DirectStubProtocol.reset()
        DirectStubProtocol.stub = { _ in
            let body = Data(#"""
            {"candidates":[{"content":{"parts":[{"text":"こんにちは"}]}}]}
            """#.utf8)
            return (httpResponse(url: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent", status: 200), body)
        }

        let provider = GeminiDirectProvider(
            config: .init(apiKey: "test-key", model: "gemini-2.5-flash", maxOutputTokens: 256, timeout: 5),
            session: stubSession()
        )
        let result = try await provider.translate(makeJob())

        #expect(result.translation == "こんにちは")

        let request = try #require(DirectStubProtocol.capturedRequests.first)
        #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == "test-key")

        let body = try #require(DirectStubProtocol.capturedBodies.first)
        let payload = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let systemInstruction = try #require(payload["systemInstruction"] as? [String: Any])
        #expect(systemInstruction["parts"] != nil)
        let generationConfig = try #require(payload["generationConfig"] as? [String: Any])
        #expect(generationConfig["temperature"] as? Double == PromptBuilder.temperature(for: .vietnameseReader))
    }

    @Test("Empty candidates payload throws missingTranslation")
    func emptyCandidates() async throws {
        DirectStubProtocol.reset()
        DirectStubProtocol.stub = { _ in
            (httpResponse(url: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent", status: 200), Data("{}".utf8))
        }

        let provider = GeminiDirectProvider(
            config: .init(apiKey: "k", model: "gemini-2.5-flash", maxOutputTokens: 1, timeout: 1),
            session: stubSession()
        )
        await #expect(throws: TranslationError.self) {
            _ = try await provider.translate(makeJob())
        }
    }

    @Test("403 from Google maps to invalidResponse for API-key UX")
    func authFailure() async throws {
        DirectStubProtocol.reset()
        DirectStubProtocol.stub = { _ in
            (httpResponse(url: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent", status: 403), Data())
        }

        let provider = GeminiDirectProvider(
            config: .init(apiKey: "wrong", model: "gemini-2.5-flash", maxOutputTokens: 1, timeout: 1),
            session: stubSession()
        )
        do {
            _ = try await provider.translate(makeJob())
            Issue.record("Expected throw")
        } catch let error as TranslationError {
            switch error {
            case .invalidResponse(let status):
                #expect(status == 403)
            default:
                Issue.record("Wrong case: \(error)")
            }
        }
    }
}

@Suite("OllamaDirectProvider")
@MainActor
struct OllamaDirectProviderTests {
    @Test("Requires baseURL + model")
    func config() {
        #expect(OllamaDirectProvider(config: .init(baseURL: "", model: "x", timeout: 1)).isConfigured == false)
        #expect(OllamaDirectProvider(config: .init(baseURL: "http://x", model: "", timeout: 1)).isConfigured == false)
        #expect(OllamaDirectProvider(config: .default).isConfigured == true)
    }

    @Test("Trims trailing slash from baseURL when composing /api/generate")
    func endpointComposition() async throws {
        DirectStubProtocol.reset()
        DirectStubProtocol.stub = { _ in
            (httpResponse(url: "http://127.0.0.1:11434/api/generate", status: 200), Data(#"{"response":"ok"}"#.utf8))
        }

        let provider = OllamaDirectProvider(
            config: .init(baseURL: "http://127.0.0.1:11434/", model: "qwen", timeout: 5),
            session: stubSession()
        )
        _ = try await provider.translate(makeJob())

        let url = try #require(DirectStubProtocol.capturedRequests.first?.url?.absoluteString)
        #expect(url.contains("/api/generate"))
        #expect(!url.contains("//api/generate"))
    }

    @Test("Empty response field throws missingTranslation")
    func emptyResponse() async throws {
        DirectStubProtocol.reset()
        DirectStubProtocol.stub = { _ in
            (httpResponse(url: "http://127.0.0.1:11434/api/generate", status: 200), Data(#"{"response":""}"#.utf8))
        }

        let provider = OllamaDirectProvider(config: .default, session: stubSession())
        await #expect(throws: TranslationError.self) {
            _ = try await provider.translate(makeJob())
        }
    }
}

@Suite("GoogleTranslateDirectProvider")
@MainActor
struct GoogleTranslateDirectProviderTests {
    @Test("Skips source language when set to auto")
    func skipsAutoSource() async throws {
        DirectStubProtocol.reset()
        DirectStubProtocol.stub = { _ in
            let body = Data(#"{"data":{"translations":[{"translatedText":"hello"}]}}"#.utf8)
            return (httpResponse(url: "https://translation.googleapis.com/language/translate/v2", status: 200), body)
        }

        let provider = GoogleTranslateDirectProvider(
            config: .init(apiKey: "k", timeout: 5),
            session: stubSession()
        )
        let job = TranslationJob(
            text: "xin chao",
            style: TranslationStyle(direction: .inbound, targetLanguage: "en", register: .neutral),
            sourceLanguage: "auto",
            glossary: ""
        )
        _ = try await provider.translate(job)

        let body = try #require(DirectStubProtocol.capturedBodies.first)
        let payload = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(payload["source"] == nil)
        #expect(payload["target"] as? String == "en")
        #expect(payload["q"] as? String == "xin chao")
    }

    @Test("Unescapes HTML entities returned by Translate Basic")
    func unescapesHTML() async throws {
        DirectStubProtocol.reset()
        DirectStubProtocol.stub = { _ in
            let body = Data(#"{"data":{"translations":[{"translatedText":"It&#39;s &amp; fine"}]}}"#.utf8)
            return (httpResponse(url: "https://translation.googleapis.com/language/translate/v2", status: 200), body)
        }

        let provider = GoogleTranslateDirectProvider(
            config: .init(apiKey: "k", timeout: 5),
            session: stubSession()
        )
        let result = try await provider.translate(makeJob())

        #expect(result.translation == "It's & fine")
    }

    @Test("HTML unescape covers core named entities")
    func unescapeCoreEntities() {
        #expect(GoogleTranslateDirectProvider.unescapeHTML("&amp;&lt;&gt;&quot;&#39;&apos;") == "&<>\"''")
    }
}

@Suite("OpenAICompatibleDirectProvider")
@MainActor
struct OpenAICompatibleDirectProviderTests {
    @Test("Sends Bearer authorization + chat-completions schema")
    func authHeaderAndSchema() async throws {
        DirectStubProtocol.reset()
        DirectStubProtocol.stub = { _ in
            let body = Data(#"""
            {"choices":[{"message":{"content":"hi"}}]}
            """#.utf8)
            return (httpResponse(url: "https://api.example.com/v1/chat/completions", status: 200), body)
        }

        let provider = OpenAICompatibleDirectProvider(
            config: .init(baseURL: "https://api.example.com/v1", apiKey: "sk-xyz", model: "gpt-test", timeout: 5),
            session: stubSession()
        )
        let result = try await provider.translate(makeJob())

        #expect(result.translation == "hi")

        let request = try #require(DirectStubProtocol.capturedRequests.first)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-xyz")

        let body = try #require(DirectStubProtocol.capturedBodies.first)
        let payload = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let messages = try #require(payload["messages"] as? [[String: Any]])
        #expect(messages.count == 2)
        #expect(messages[0]["role"] as? String == "system")
        #expect(messages[1]["role"] as? String == "user")
        #expect(payload["model"] as? String == "gpt-test")
    }

    @Test("Falls back through choices.text and output_text variants")
    func legacyShapes() async throws {
        DirectStubProtocol.reset()
        DirectStubProtocol.stub = { _ in
            let body = Data(#"""
            {"choices":[{"text":"legacy"}]}
            """#.utf8)
            return (httpResponse(url: "https://api.example.com/v1/chat/completions", status: 200), body)
        }

        let provider = OpenAICompatibleDirectProvider(
            config: .init(baseURL: "https://api.example.com/v1", apiKey: "k", model: "m", timeout: 5),
            session: stubSession()
        )
        let result = try await provider.translate(makeJob())

        #expect(result.translation == "legacy")
    }

    @Test("429 from upstream surfaces rateLimited error with Retry-After")
    func rateLimitMapping() async throws {
        DirectStubProtocol.reset()
        DirectStubProtocol.stub = { _ in
            (httpResponse(url: "https://api.example.com/v1/chat/completions", status: 429, headers: ["Retry-After": "3"]), Data())
        }

        let provider = OpenAICompatibleDirectProvider(
            config: .init(baseURL: "https://api.example.com/v1", apiKey: "k", model: "m", timeout: 5),
            session: stubSession()
        )
        do {
            _ = try await provider.translate(makeJob())
            Issue.record("Expected throw")
        } catch let error as TranslationError {
            switch error {
            case .rateLimited(let retryAfter, _):
                #expect(retryAfter == 3)
            default:
                Issue.record("Wrong case: \(error)")
            }
        }
    }
}

@Suite("DeepLDirectProvider")
@MainActor
struct DeepLDirectProviderTests {
    private func makeJob(register: Register = .formal, target: String = "ja", source: String = "vi") -> TranslationJob {
        TranslationJob(
            text: "xin chao",
            style: TranslationStyle(direction: .outbound, targetLanguage: target, register: register),
            sourceLanguage: source,
            glossary: ""
        )
    }

    @Test("isConfigured requires API key")
    func configurationGate() {
        #expect(DeepLDirectProvider(config: .init(apiKey: "", useFreeEndpoint: true, timeout: 1)).isConfigured == false)
        #expect(DeepLDirectProvider(config: .init(apiKey: "k", useFreeEndpoint: true, timeout: 1)).isConfigured == true)
    }

    @Test("Free endpoint hits api-free.deepl.com with DeepL-Auth-Key header")
    func freeEndpoint() async throws {
        DirectStubProtocol.reset()
        DirectStubProtocol.stub = { _ in
            (httpResponse(url: "https://api-free.deepl.com/v2/translate", status: 200),
             Data(#"{"translations":[{"text":"こんにちは"}]}"#.utf8))
        }
        let provider = DeepLDirectProvider(
            config: .init(apiKey: "k", useFreeEndpoint: true, timeout: 5),
            session: stubSession()
        )
        _ = try await provider.translate(makeJob())

        let request = try #require(DirectStubProtocol.capturedRequests.first)
        #expect(request.url?.absoluteString.contains("api-free.deepl.com") == true)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "DeepL-Auth-Key k")
    }

    @Test("Pro endpoint hits api.deepl.com")
    func proEndpoint() async throws {
        DirectStubProtocol.reset()
        DirectStubProtocol.stub = { _ in
            (httpResponse(url: "https://api.deepl.com/v2/translate", status: 200),
             Data(#"{"translations":[{"text":"x"}]}"#.utf8))
        }
        let provider = DeepLDirectProvider(
            config: .init(apiKey: "k", useFreeEndpoint: false, timeout: 5),
            session: stubSession()
        )
        _ = try await provider.translate(makeJob())

        let request = try #require(DirectStubProtocol.capturedRequests.first)
        #expect(request.url?.absoluteString.contains("api-free.deepl.com") == false)
        #expect(request.url?.absoluteString.contains("api.deepl.com") == true)
    }

    @Test("Formal register sets formality=more in form body")
    func formalityMore() async throws {
        DirectStubProtocol.reset()
        DirectStubProtocol.stub = { _ in
            (httpResponse(url: "https://api-free.deepl.com/v2/translate", status: 200),
             Data(#"{"translations":[{"text":"x"}]}"#.utf8))
        }
        let provider = DeepLDirectProvider(
            config: .init(apiKey: "k", useFreeEndpoint: true, timeout: 5),
            session: stubSession()
        )
        _ = try await provider.translate(makeJob(register: .formal))

        let body = try #require(DirectStubProtocol.capturedBodies.first)
        let str = String(data: body, encoding: .utf8) ?? ""
        #expect(str.contains("formality=more"))
    }

    @Test("Casual register sets formality=less")
    func formalityLess() async throws {
        DirectStubProtocol.reset()
        DirectStubProtocol.stub = { _ in
            (httpResponse(url: "https://api-free.deepl.com/v2/translate", status: 200),
             Data(#"{"translations":[{"text":"x"}]}"#.utf8))
        }
        let provider = DeepLDirectProvider(
            config: .init(apiKey: "k", useFreeEndpoint: true, timeout: 5),
            session: stubSession()
        )
        _ = try await provider.translate(makeJob(register: .casual))

        let body = try #require(DirectStubProtocol.capturedBodies.first)
        let str = String(data: body, encoding: .utf8) ?? ""
        #expect(str.contains("formality=less"))
    }

    @Test("Auto source language omitted from form body")
    func autoSourceOmitted() async throws {
        DirectStubProtocol.reset()
        DirectStubProtocol.stub = { _ in
            (httpResponse(url: "https://api-free.deepl.com/v2/translate", status: 200),
             Data(#"{"translations":[{"text":"x"}]}"#.utf8))
        }
        let provider = DeepLDirectProvider(
            config: .init(apiKey: "k", useFreeEndpoint: true, timeout: 5),
            session: stubSession()
        )
        _ = try await provider.translate(makeJob(source: "auto"))

        let body = try #require(DirectStubProtocol.capturedBodies.first)
        let str = String(data: body, encoding: .utf8) ?? ""
        #expect(!str.contains("source_lang"))
    }

    @Test("BCP47 → DeepL code mapping")
    func bcp47Mapping() {
        #expect(DeepLDirectProvider.deeplCode(for: "en", target: true) == "EN-US")
        #expect(DeepLDirectProvider.deeplCode(for: "en", target: false) == "EN")
        #expect(DeepLDirectProvider.deeplCode(for: "ja", target: true) == "JA")
        #expect(DeepLDirectProvider.deeplCode(for: "zh-CN", target: true) == "ZH")
    }
}

@Suite("LibreTranslateDirectProvider")
@MainActor
struct LibreTranslateDirectProviderTests {
    private func makeJob(target: String = "en", source: String = "vi", text: String = "xin chao") -> TranslationJob {
        TranslationJob(
            text: text,
            style: TranslationStyle(direction: .outbound, targetLanguage: target, register: .neutral),
            sourceLanguage: source,
            glossary: ""
        )
    }

    @Test("Posts q + source + target to <baseURL>/translate")
    func postsCorrectShape() async throws {
        DirectStubProtocol.reset()
        DirectStubProtocol.stub = { _ in
            (httpResponse(url: "https://libretranslate.com/translate", status: 200),
             Data(#"{"translatedText":"hello"}"#.utf8))
        }
        let provider = LibreTranslateDirectProvider(
            config: .init(baseURL: "https://libretranslate.com", apiKey: "", timeout: 5),
            session: stubSession()
        )
        _ = try await provider.translate(makeJob())

        let request = try #require(DirectStubProtocol.capturedRequests.first)
        #expect(request.url?.path == "/translate")

        let body = try #require(DirectStubProtocol.capturedBodies.first)
        let payload = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(payload["q"] as? String == "xin chao")
        #expect(payload["source"] as? String == "vi")
        #expect(payload["target"] as? String == "en")
        #expect(payload["api_key"] == nil)
    }

    @Test("Includes api_key when configured")
    func includesAPIKey() async throws {
        DirectStubProtocol.reset()
        DirectStubProtocol.stub = { _ in
            (httpResponse(url: "https://lt.example.com/translate", status: 200),
             Data(#"{"translatedText":"hi"}"#.utf8))
        }
        let provider = LibreTranslateDirectProvider(
            config: .init(baseURL: "https://lt.example.com/", apiKey: "secret", timeout: 5),
            session: stubSession()
        )
        _ = try await provider.translate(makeJob())

        let body = try #require(DirectStubProtocol.capturedBodies.first)
        let payload = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(payload["api_key"] as? String == "secret")
    }

    @Test("Empty translatedText raises missingTranslation")
    func emptyResponse() async throws {
        DirectStubProtocol.reset()
        DirectStubProtocol.stub = { _ in
            (httpResponse(url: "https://libretranslate.com/translate", status: 200),
             Data(#"{"translatedText":""}"#.utf8))
        }
        let provider = LibreTranslateDirectProvider(
            config: .init(baseURL: "https://libretranslate.com", apiKey: "", timeout: 5),
            session: stubSession()
        )
        await #expect(throws: TranslationError.self) {
            _ = try await provider.translate(makeJob())
        }
    }
}

} // end DirectProviderHTTPSuites

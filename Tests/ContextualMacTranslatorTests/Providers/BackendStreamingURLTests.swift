import Foundation
import Testing

@testable import ContextualMacTranslator

/// v0.9.1 — parameterised tests for `BackendProvider.streamingURL(for:)`.
/// The 4-case path rewriter was untested in v0.9.0 (code-review W3.5);
/// these pin every branch + the silent-fallback edge case the review
/// flagged.
@Suite("BackendProvider.streamingURL path rewriter")
struct BackendStreamingURLTests {

    @Test("Standard /translate endpoint becomes /translate/stream")
    func standardEndpoint() {
        let in_ = URL(string: "https://api.example.com/translate")!
        let out = BackendProvider.streamingURL(for: in_)
        #expect(out.absoluteString == "https://api.example.com/translate/stream")
    }

    @Test("Bare root (no path) becomes /translate/stream")
    func bareRoot() {
        let in_ = URL(string: "https://api.example.com")!
        let out = BackendProvider.streamingURL(for: in_)
        #expect(out.absoluteString == "https://api.example.com/translate/stream")
    }

    @Test("Explicit slash root (/) becomes /translate/stream")
    func slashRoot() {
        let in_ = URL(string: "https://api.example.com/")!
        let out = BackendProvider.streamingURL(for: in_)
        #expect(out.absoluteString == "https://api.example.com/translate/stream")
    }

    @Test("Trailing-slash custom path appends translate/stream")
    func trailingSlashCustom() {
        // User-configured /api/ → /api/translate/stream
        let in_ = URL(string: "https://api.example.com/api/")!
        let out = BackendProvider.streamingURL(for: in_)
        #expect(out.absoluteString == "https://api.example.com/api/translate/stream")
    }

    @Test("Custom path without trailing slash appends /stream")
    func customPathAppendsStream() {
        // User-configured /api/translate → /api/translate/stream
        let in_ = URL(string: "https://api.example.com/api/translate")!
        let out = BackendProvider.streamingURL(for: in_)
        #expect(out.absoluteString == "https://api.example.com/api/translate/stream")
    }

    @Test("Versioned path /api/v2/translate becomes /api/v2/translate/stream")
    func versionedPath() {
        let in_ = URL(string: "https://api.example.com/api/v2/translate")!
        let out = BackendProvider.streamingURL(for: in_)
        #expect(out.absoluteString == "https://api.example.com/api/v2/translate/stream")
    }

    @Test("Non-translate suffix (/api/v2/something) silently gets /stream appended")
    func nonTranslateSuffix() {
        // This is the edge case the review flagged — the rewriter has
        // no validation, it just appends /stream. Pin the current
        // behaviour so a future "be smarter about non-translate paths"
        // change is a conscious decision rather than a regression.
        let in_ = URL(string: "https://api.example.com/api/v2/something")!
        let out = BackendProvider.streamingURL(for: in_)
        #expect(out.absoluteString == "https://api.example.com/api/v2/something/stream")
    }

    @Test("Query strings on the endpoint pass through unmodified")
    func querySurvives() {
        let in_ = URL(string: "https://api.example.com/translate?debug=1")!
        let out = BackendProvider.streamingURL(for: in_)
        #expect(out.absoluteString == "https://api.example.com/translate/stream?debug=1")
    }

    @Test("Non-default port survives")
    func portSurvives() {
        let in_ = URL(string: "https://api.example.com:8443/translate")!
        let out = BackendProvider.streamingURL(for: in_)
        #expect(out.absoluteString == "https://api.example.com:8443/translate/stream")
    }
}

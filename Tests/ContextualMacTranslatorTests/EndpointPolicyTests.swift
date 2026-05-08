import Foundation
import Testing

@testable import ContextualMacTranslator

@Suite("EndpointPolicy")
struct EndpointPolicyTests {
    @Test("allows HTTPS remote endpoints")
    func allowsHTTPSRemote() throws {
        let url = try #require(URL(string: "https://translator.example.com/translate"))

        #expect(EndpointPolicy.allows(url) == true)
    }

    @Test("allows HTTP loopback endpoints")
    func allowsHTTPLoopback() throws {
        let urls = [
            "http://127.0.0.1:8765/translate",
            "http://localhost:8765/translate",
            "http://[::1]:8765/translate"
        ]

        for value in urls {
            let url = try #require(URL(string: value))
            #expect(EndpointPolicy.allows(url) == true)
        }
    }

    @Test("rejects HTTP remote endpoints")
    func rejectsHTTPRemote() throws {
        let url = try #require(URL(string: "http://translator.example.com/translate"))

        #expect(EndpointPolicy.allows(url) == false)
    }

    @Test("rejects non-HTTP schemes")
    func rejectsNonHTTPSchemes() throws {
        let url = try #require(URL(string: "file:///tmp/translate"))

        #expect(EndpointPolicy.allows(url) == false)
    }

    @Test("settings warning appears only for insecure remote endpoints")
    func settingsWarning() {
        #expect(EndpointPolicy.warning(for: "http://translator.example.com/translate") != nil)
        #expect(EndpointPolicy.warning(for: "http://127.0.0.1:8765/translate") == nil)
        #expect(EndpointPolicy.warning(for: "https://translator.example.com/translate") == nil)
    }
}

import Foundation
import Testing

@testable import ContextualMacTranslator

// MARK: - Mock translator

/// In-memory `HeadlessTranslator` for intent tests. Configurable per
/// test to either return canned strings or throw chosen errors, with a
/// call log to assert parameters reached the right method.
@MainActor
private final class StubHeadlessTranslator: HeadlessTranslator {
    enum Call: Equatable {
        case translate(text: String, target: String)
        case rewriteTone(text: String, tone: RewriteTone)
        case rewriteInstruction(text: String, instruction: String)
    }

    var calls: [Call] = []
    var translateResult: Result<String, Error> = .success("translated")
    var rewriteToneResult: Result<String, Error> = .success("rewritten-tone")
    var rewriteInstructionResult: Result<String, Error> = .success("rewritten-instruction")

    func translateHeadless(text: String, targetLanguage: String) async throws -> String {
        calls.append(.translate(text: text, target: targetLanguage))
        return try translateResult.get()
    }

    func rewriteHeadless(text: String, tone: RewriteTone) async throws -> String {
        calls.append(.rewriteTone(text: text, tone: tone))
        return try rewriteToneResult.get()
    }

    func rewriteHeadless(text: String, instruction: String) async throws -> String {
        calls.append(.rewriteInstruction(text: text, instruction: instruction))
        return try rewriteInstructionResult.get()
    }
}

@MainActor
private func install(_ stub: StubHeadlessTranslator) {
    TranslationIntentRouter.shared.install(stub)
}

@MainActor
private func reset() {
    // Restore the uninstalled default after each test so other tests
    // don't see leftover state from this suite.
    TranslationIntentRouter.shared.install(UninstalledForTests())
}

@MainActor
private final class UninstalledForTests: HeadlessTranslator {
    func translateHeadless(text: String, targetLanguage: String) async throws -> String {
        throw TranslationIntentError.missingProvider
    }
    func rewriteHeadless(text: String, tone: RewriteTone) async throws -> String {
        throw TranslationIntentError.missingProvider
    }
    func rewriteHeadless(text: String, instruction: String) async throws -> String {
        throw TranslationIntentError.missingProvider
    }
}

// MARK: - Tone mirror

@Suite("RewriteToneAppEnum mirror")
struct RewriteToneAppEnumTests {
    @Test("All preset cases map back to the matching RewriteTone")
    func mirrorMaps() {
        // Mirror should NOT include casualRaw (gated by expressive
        // toggle, not exposed to Shortcuts in v0.9.0).
        let expected: [(RewriteToneAppEnum, RewriteTone)] = [
            (.polite, .polite),
            (.professional, .professional),
            (.friendly, .friendly),
            (.firmButPolite, .firmButPolite),
            (.deEscalate, .deEscalate),
            (.concise, .concise),
            (.custom, .custom),
        ]
        for (mirror, expected) in expected {
            #expect(mirror.rewriteTone == expected)
        }
    }

    @Test("Mirror excludes the expressive tone (casualRaw)")
    func excludesExpressive() {
        // Sanity check: if someone adds `case casualRaw` to the mirror
        // without thinking about Shortcuts gating, this test fires.
        let exposed = Set(RewriteToneAppEnum.allCases.map(\.rewriteTone))
        #expect(!exposed.contains(.casualRaw))
        #expect(exposed.count == 7)
    }
}

// MARK: - TranslateSelectionIntent

@Suite("TranslateSelectionIntent")
@MainActor
struct TranslateSelectionIntentTests {
    @Test("Empty targetLanguage falls back to primaryLanguage")
    func emptyTargetFallsBackToPrimary() async throws {
        let stub = StubHeadlessTranslator()
        install(stub)
        defer { reset() }

        let intent = TranslateSelectionIntent()
        intent.text = "hello"
        intent.targetLanguage = ""
        _ = try await intent.perform()

        let primary = SettingsStore.shared.primaryLanguage
        #expect(stub.calls == [.translate(text: "hello", target: primary)])
    }

    @Test("Explicit targetLanguage is passed through verbatim")
    func explicitTargetPassesThrough() async throws {
        let stub = StubHeadlessTranslator()
        install(stub)
        defer { reset() }

        let intent = TranslateSelectionIntent()
        intent.text = "Bonjour"
        intent.targetLanguage = "vi"
        _ = try await intent.perform()

        #expect(stub.calls == [.translate(text: "Bonjour", target: "vi")])
    }

    @Test("TranslationError.missingEndpoint surfaces as providerNotConfigured")
    func mapsMissingEndpoint() async {
        let stub = StubHeadlessTranslator()
        stub.translateResult = .failure(TranslationError.missingEndpoint)
        install(stub)
        defer { reset() }

        let intent = TranslateSelectionIntent()
        intent.text = "hi"
        intent.targetLanguage = "vi"

        do {
            _ = try await intent.perform()
            Issue.record("expected intent to throw")
        } catch let error as TranslationIntentError {
            #expect(error == .providerNotConfigured)
        } catch {
            Issue.record("expected TranslationIntentError, got \(type(of: error))")
        }
    }
}

// MARK: - RewriteWithToneIntent

@Suite("RewriteWithToneIntent")
@MainActor
struct RewriteWithToneIntentTests {
    @Test("Preset tone routes to rewriteHeadless(text:tone:) with the right enum")
    func presetTonePropagates() async throws {
        let stub = StubHeadlessTranslator()
        install(stub)
        defer { reset() }

        let intent = RewriteWithToneIntent()
        intent.text = "wanna meet 2morrow"
        intent.tone = .professional
        _ = try await intent.perform()

        #expect(stub.calls == [.rewriteTone(text: "wanna meet 2morrow", tone: .professional)])
    }

    @Test("RewriteError.refused surfaces as TranslationIntentError.refused")
    func mapsRefusal() async {
        let stub = StubHeadlessTranslator()
        stub.rewriteToneResult = .failure(RewriteError.refused)
        install(stub)
        defer { reset() }

        let intent = RewriteWithToneIntent()
        intent.text = "x"
        intent.tone = .polite

        do {
            _ = try await intent.perform()
            Issue.record("expected intent to throw")
        } catch let error as TranslationIntentError {
            #expect(error == .refused)
        } catch {
            Issue.record("expected TranslationIntentError, got \(type(of: error))")
        }
    }
}

// MARK: - RewriteWithPromptIntent

@Suite("RewriteWithPromptIntent")
@MainActor
struct RewriteWithPromptIntentTests {
    @Test("Trimmed non-empty instruction is forwarded")
    func instructionForwarded() async throws {
        let stub = StubHeadlessTranslator()
        install(stub)
        defer { reset() }

        let intent = RewriteWithPromptIntent()
        intent.text = "y"
        intent.instruction = "  shorter under 2 sentences  "
        _ = try await intent.perform()

        #expect(stub.calls == [.rewriteInstruction(text: "y", instruction: "shorter under 2 sentences")])
    }

    @Test("Empty instruction (whitespace only) short-circuits with emptyInstruction error")
    func emptyInstructionShortCircuits() async {
        let stub = StubHeadlessTranslator()
        install(stub)
        defer { reset() }

        let intent = RewriteWithPromptIntent()
        intent.text = "y"
        intent.instruction = "   "

        do {
            _ = try await intent.perform()
            Issue.record("expected intent to throw")
        } catch let error as TranslationIntentError {
            #expect(error == .emptyInstruction)
        } catch {
            Issue.record("expected TranslationIntentError, got \(type(of: error))")
        }
        // Stub should never have been called for empty input.
        #expect(stub.calls.isEmpty)
    }

    @Test("RewriteError.emptyCustomInstruction from workflow also surfaces as emptyInstruction")
    func emptyInstructionFromWorkflow() async {
        let stub = StubHeadlessTranslator()
        stub.rewriteInstructionResult = .failure(RewriteError.emptyCustomInstruction)
        install(stub)
        defer { reset() }

        let intent = RewriteWithPromptIntent()
        intent.text = "y"
        intent.instruction = "make it shorter"

        do {
            _ = try await intent.perform()
            Issue.record("expected intent to throw")
        } catch let error as TranslationIntentError {
            #expect(error == .emptyInstruction)
        } catch {
            Issue.record("expected TranslationIntentError, got \(type(of: error))")
        }
    }
}

// MARK: - Error mapping

@Suite("TranslationIntentError.from(_:)")
struct TranslationIntentErrorMappingTests {
    @Test("Already-typed intent error passes through unchanged")
    func passesThroughIntentError() {
        let original = TranslationIntentError.refused
        let mapped = TranslationIntentError.from(original)
        #expect(mapped == .refused)
    }

    @Test("RewriteError.refused → .refused")
    func refusalMaps() {
        #expect(TranslationIntentError.from(RewriteError.refused) == .refused)
    }

    @Test("RewriteError.emptyCustomInstruction → .emptyInstruction")
    func emptyMaps() {
        #expect(TranslationIntentError.from(RewriteError.emptyCustomInstruction) == .emptyInstruction)
    }

    @Test("TranslationError.missingEndpoint → .providerNotConfigured")
    func missingEndpointMaps() {
        #expect(TranslationIntentError.from(TranslationError.missingEndpoint) == .providerNotConfigured)
    }

    @Test("Unknown error is wrapped, preserving the localized message")
    func unknownErrorWrapped() {
        struct WeirdError: LocalizedError {
            var errorDescription: String? { "kaboom" }
        }
        let mapped = TranslationIntentError.from(WeirdError())
        #expect(mapped.localizedDescription == "kaboom")
    }
}

// Equatable conformance for the test assertions above. The production
// enum doesn't need it for normal use — only the tests pattern-match
// on cases — but `#expect(... == ...)` reads cleaner than nested do/catch.
extension TranslationIntentError: Equatable {
    public static func == (lhs: TranslationIntentError, rhs: TranslationIntentError) -> Bool {
        switch (lhs, rhs) {
        case (.missingProvider, .missingProvider),
             (.providerNotConfigured, .providerNotConfigured),
             (.emptyInstruction, .emptyInstruction),
             (.refused, .refused):
            return true
        case (.wrapped(let l), .wrapped(let r)):
            return l == r
        default:
            return false
        }
    }
}

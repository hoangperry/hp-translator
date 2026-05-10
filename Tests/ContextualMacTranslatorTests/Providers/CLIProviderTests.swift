import Foundation
import Testing

@testable import ContextualMacTranslator

// MARK: - Stub runner

/// Simple reference-type box so test bodies can record values from inside
/// `@Sendable` runner closures without bumping into Swift 6 concurrency
/// diagnostics for captured `var`.
private final class CaptureBox: @unchecked Sendable {
    var executable: String = ""
    var arguments: [String] = []
    var stdin: String?
    var timeout: TimeInterval = 0
}

private struct StubProcessRunner: ProcessRunner, @unchecked Sendable {
    let result: ProcessResult
    let capture: CaptureBox?

    init(
        exitCode: Int32 = 0,
        stdout: String = "",
        stderr: String = "",
        capture: CaptureBox? = nil
    ) {
        self.result = ProcessResult(exitCode: exitCode, stdout: stdout, stderr: stderr)
        self.capture = capture
    }

    func run(executable: String, arguments: [String], stdin: String?, timeout: TimeInterval) async throws -> ProcessResult {
        if let capture {
            capture.executable = executable
            capture.arguments = arguments
            capture.stdin = stdin
            capture.timeout = timeout
        }
        return result
    }
}

private func makeJob() -> TranslationJob {
    TranslationJob(text: "xin chao", style: .vietnameseReader, sourceLanguage: "auto", glossary: ""
    )
}

// MARK: - CLIOutputExtractor

@Suite("CLIOutputExtractor")
struct CLIOutputExtractorTests {
    @Test("Returns plain stdout when not JSON")
    func plainStdout() {
        #expect(CLIOutputExtractor.extractText(from: "hello\n") == "hello")
    }

    @Test("Extracts response key from JSON")
    func responseKey() {
        let json = #"{"response":"こんにちは"}"#
        #expect(CLIOutputExtractor.extractText(from: json) == "こんにちは")
    }

    @Test("Walks Gemini-style candidates structure")
    func geminiShape() {
        let json = #"""
        {"candidates":[{"content":{"parts":[{"text":"Xin chao"}]}}]}
        """#
        #expect(CLIOutputExtractor.extractText(from: json) == "Xin chao")
    }

    @Test("Returns nil for empty input")
    func emptyInput() {
        #expect(CLIOutputExtractor.extractText(from: "   ") == nil)
        #expect(CLIOutputExtractor.extractText(from: "") == nil)
    }

    @Test("Falls back when JSON has no recognised text key")
    func unrecognisedJSON() {
        let json = #"{"unrelated":"value"}"#
        #expect(CLIOutputExtractor.extractText(from: json) == nil)
    }
}

// MARK: - GeminiCLI

@Suite("GeminiCLIProvider")
@MainActor
struct GeminiCLIProviderTests {
    @Test("Sends -p prompt + --output-format json arguments")
    func argumentsShape() async throws {
        let capture = CaptureBox()
        let runner = StubProcessRunner(
            exitCode: 0,
            stdout: #"{"response":"Xin chào"}"#,
            capture: capture
        )
        let provider = GeminiCLIProvider(config: .init(command: "gemini", model: "gemini-2.5-flash", timeout: 5), runner: runner)

        let result = try await provider.translate(makeJob())

        #expect(result.translation == "Xin chào")
        #expect(capture.executable == "gemini")
        #expect(capture.arguments.contains("--output-format"))
        #expect(capture.arguments.contains("json"))
        #expect(capture.arguments.contains("-m"))
        #expect(capture.arguments.contains("gemini-2.5-flash"))
        if let promptIndex = capture.arguments.firstIndex(of: "-p"), promptIndex + 1 < capture.arguments.count {
            #expect(capture.arguments[promptIndex + 1].contains("Register: neutral"))
            #expect(capture.arguments[promptIndex + 1].contains("Target language: vi"))
        } else {
            Issue.record("`-p <prompt>` not found in args: \(capture.arguments)")
        }
    }

    @Test("Skips -m when model is empty")
    func optionalModel() async throws {
        let capture = CaptureBox()
        let runner = StubProcessRunner(stdout: #"{"response":"hi"}"#, capture: capture)
        let provider = GeminiCLIProvider(config: .init(command: "gemini", model: "", timeout: 5), runner: runner)

        _ = try await provider.translate(makeJob())

        #expect(!capture.arguments.contains("-m"))
    }

    @Test("Non-zero exit raises serverProblem")
    func nonZeroExit() async throws {
        let runner = StubProcessRunner(exitCode: 2, stderr: "auth failed")
        let provider = GeminiCLIProvider(config: .default, runner: runner)

        do {
            _ = try await provider.translate(makeJob())
            Issue.record("Expected throw")
        } catch let error as TranslationError {
            switch error {
            case .serverProblem(_, _, let detail):
                #expect((detail ?? "").contains("auth failed"))
            default:
                Issue.record("Wrong case: \(error)")
            }
        }
    }

    @Test("Empty stdout raises missingTranslation")
    func emptyStdout() async throws {
        let runner = StubProcessRunner(stdout: "")
        let provider = GeminiCLIProvider(config: .default, runner: runner)

        do {
            _ = try await provider.translate(makeJob())
            Issue.record("Expected throw")
        } catch let error as TranslationError {
            switch error {
            case .missingTranslation:
                break
            default:
                Issue.record("Wrong case: \(error)")
            }
        }
    }
}

// MARK: - CodexCLI

@Suite("CodexCLIProvider")
@MainActor
struct CodexCLIProviderTests {
    @Test("Sends `exec` + sandbox + ephemeral args")
    func argumentsShape() async throws {
        let capture = CaptureBox()
        let runner = StubProcessRunner(stdout: "Xin chào", capture: capture)
        let provider = CodexCLIProvider(config: .default, runner: runner)

        _ = try await provider.translate(makeJob())

        #expect(capture.arguments.contains("exec"))
        #expect(capture.arguments.contains("--ephemeral"))
        #expect(capture.arguments.contains("--sandbox"))
        #expect(capture.arguments.contains("read-only"))
        #expect(capture.arguments.contains("--skip-git-repo-check"))
    }

    @Test("Adds --oss + --local-provider when configured for OSS")
    func ossPath() async throws {
        let capture = CaptureBox()
        let runner = StubProcessRunner(stdout: "x", capture: capture)
        let provider = CodexCLIProvider(
            config: .init(command: "codex", model: "", timeout: 5, useOSS: true, localProvider: "ollama"),
            runner: runner
        )

        _ = try await provider.translate(makeJob())

        #expect(capture.arguments.contains("--oss"))
        #expect(capture.arguments.contains("--local-provider"))
        #expect(capture.arguments.contains("ollama"))
    }

    @Test("Plain text stdout is taken as-is")
    func plainStdout() async throws {
        let runner = StubProcessRunner(stdout: "Translated text\n")
        let provider = CodexCLIProvider(config: .default, runner: runner)

        let result = try await provider.translate(makeJob())

        #expect(result.translation == "Translated text")
    }

    @Test("Non-zero exit raises serverProblem")
    func nonZeroExit() async throws {
        let runner = StubProcessRunner(exitCode: 1, stdout: "", stderr: "sandbox blocked")
        let provider = CodexCLIProvider(config: .default, runner: runner)

        do {
            _ = try await provider.translate(makeJob())
            Issue.record("Expected throw")
        } catch let error as TranslationError {
            switch error {
            case .serverProblem(_, _, let detail):
                #expect((detail ?? "").contains("sandbox"))
            default:
                Issue.record("Wrong case: \(error)")
            }
        }
    }
}

// MARK: - PATH augmentation

@Suite("SystemProcessRunner PATH")
struct SystemProcessRunnerPathTests {
    @Test("Includes Homebrew + user-local bin ahead of inherited PATH")
    func extendsPath() {
        let env = SystemProcessRunner.augmentedEnvironment()
        let path = env["PATH"] ?? ""
        let parts = path.split(separator: ":").map(String.init)

        // First entry must be Homebrew so /opt/homebrew/bin/codex wins
        // over any stale system shim earlier in the inherited PATH.
        #expect(parts.first == "/opt/homebrew/bin")
        #expect(parts.contains("/usr/local/bin"))
        // Inherited /usr/bin still present so system tools work.
        #expect(parts.contains("/usr/bin"))
    }

    @Test("PATH entries are de-duplicated")
    func deduplicates() {
        let env = SystemProcessRunner.augmentedEnvironment()
        let parts = (env["PATH"] ?? "").split(separator: ":").map(String.init)
        #expect(parts.count == Set(parts).count)
    }
}

// MARK: - Factory wires CLI providers

@Suite("Factory CLI dispatch")
@MainActor
struct FactoryCLIDispatchTests {
    private func makeSettings(_ configure: (SettingsStore) -> Void) -> SettingsStore {
        let suiteName = "translator-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let keychain = KeychainCredentialStore(service: "translator-tests.\(UUID().uuidString)")
        let store = SettingsStore(defaults: defaults, keychain: keychain)
        configure(store)
        return store
    }

    @Test("geminiCLI source returns GeminiCLIProvider")
    func factoryReturnsGeminiCLI() {
        let settings = makeSettings { store in
            store.translationSource = .directAPI
            store.directProvider = .geminiCLI
        }
        let factory = TranslationProviderFactory(settings: settings)
        #expect(factory.make() is GeminiCLIProvider)
    }

    @Test("codexCLI source returns CodexCLIProvider")
    func factoryReturnsCodexCLI() {
        let settings = makeSettings { store in
            store.translationSource = .directAPI
            store.directProvider = .codexCLI
        }
        let factory = TranslationProviderFactory(settings: settings)
        #expect(factory.make() is CodexCLIProvider)
    }
}

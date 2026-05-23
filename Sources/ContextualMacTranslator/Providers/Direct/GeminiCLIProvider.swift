import Foundation

/// Direct provider that shells out to the `gemini` CLI for each request.
/// Mirrors Python `GeminiCLIProvider`. Slower than the API path because
/// every translation pays a process-spawn + auth-check round-trip, but
/// useful when the user already has the Gemini CLI configured and wants
/// to reuse its session.
@MainActor
final class GeminiCLIProvider: TranslationProvider {
    static var providerKey: String { "gemini-cli" }
    static var displayName: String { "Gemini CLI" }

    struct Config: Sendable {
        var command: String
        var model: String
        var timeout: TimeInterval

        static let `default` = Config(command: "gemini", model: "", timeout: 45)
    }

    private let config: Config
    private let runner: ProcessRunner

    init(config: Config, runner: ProcessRunner = SystemProcessRunner()) {
        self.config = config
        self.runner = runner
    }

    var isConfigured: Bool {
        !config.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func translate(_ job: TranslationJob) async throws -> TranslationResult {
        guard isConfigured else { throw TranslationError.missingEndpoint }

        let prompt = "\(PromptBuilder.systemPrompt(for: job))\n\n\(PromptBuilder.userPrompt(for: job))"
        var arguments: [String] = []
        if !config.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            arguments.append(contentsOf: ["-m", config.model])
        }
        arguments.append(contentsOf: ["-p", prompt, "--output-format", "json"])

        let result = try await runner.run(
            executable: config.command,
            arguments: arguments,
            stdin: nil,
            timeout: config.timeout
        )

        if result.exitCode != 0 {
            let detail = result.stderr.isEmpty ? result.stdout : result.stderr
            throw TranslationError.serverProblem(
                status: 502,
                title: "Gemini CLI failed",
                detail: detail.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        guard let extracted = CLIOutputExtractor.extractText(from: result.stdout),
              !extracted.isEmpty
        else {
            throw TranslationError.missingTranslation
        }
        return TranslationResult(translation: PromptBuilder.normalize(extracted))
    }
}

import Foundation

/// Direct provider that shells out to `codex exec` for each request.
/// Mirrors Python `CodexCLIProvider`. Useful when the user already has a
/// Codex login and wants to reuse it; not recommended as a primary path
/// because spawning a process per hotkey is expensive.
@MainActor
final class CodexCLIProvider: TranslationProvider {
    static var providerKey: String { "codex-cli" }
    static var displayName: String { "Codex CLI" }

    struct Config: Sendable {
        var command: String
        var model: String
        var timeout: TimeInterval
        var useOSS: Bool
        var localProvider: String

        static let `default` = Config(
            command: "codex",
            model: "",
            timeout: 60,
            useOSS: false,
            localProvider: ""
        )
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

        let prompt = """
        \(PromptBuilder.systemPrompt(for: job))

        You are being used as a translation subprocess for a menu bar app.
        Do not inspect files, run commands, ask questions, or explain your reasoning.

        \(PromptBuilder.userPrompt(for: job))
        """

        var arguments: [String] = [
            "exec",
            "--skip-git-repo-check",
            "--ephemeral",
            "--sandbox", "read-only",
            "--ignore-rules",
            "--color", "never",
        ]
        if !config.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            arguments.append(contentsOf: ["-m", config.model])
        }
        if config.useOSS {
            arguments.append("--oss")
        }
        if !config.localProvider.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            arguments.append(contentsOf: ["--local-provider", config.localProvider])
        }
        arguments.append(prompt)

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
                title: "Codex CLI failed",
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

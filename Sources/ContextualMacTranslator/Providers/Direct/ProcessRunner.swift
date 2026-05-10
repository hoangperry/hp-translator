import Foundation

/// Result of a one-shot subprocess invocation.
struct ProcessResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

/// Spawn-and-wait abstraction over `Foundation.Process`. Lives behind a
/// protocol so CLI provider tests can inject a deterministic stub instead
/// of really executing `gemini`/`codex` on the test machine.
protocol ProcessRunner: Sendable {
    /// Run `executable` with `arguments`, optionally writing `stdin` to
    /// the child. Throws if the executable cannot be located/launched.
    func run(
        executable: String,
        arguments: [String],
        stdin: String?,
        timeout: TimeInterval
    ) async throws -> ProcessResult
}

/// Production runner: literal `Foundation.Process`. We intentionally
/// resolve `executable` via `/usr/bin/env` so users can override with
/// PATH-resident binaries (e.g. `gemini`, `codex`) without specifying an
/// absolute path.
struct SystemProcessRunner: ProcessRunner {
    func run(
        executable: String,
        arguments: [String],
        stdin: String?,
        timeout: TimeInterval
    ) async throws -> ProcessResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [executable] + arguments

            // Apps launched from /Applications inherit a minimal PATH
            // (/usr/bin:/bin:/usr/sbin:/sbin) that excludes Homebrew. Without
            // this fix `gemini`/`codex` installed via brew at
            // /opt/homebrew/bin won't be found by `/usr/bin/env`.
            process.environment = Self.augmentedEnvironment()

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            if stdin != nil {
                process.standardInput = Pipe()
            }

            // Single-shot resume guard. Both the termination handler and
            // the timeout watchdog can race for the resume; whoever wins
            // first wins, the other is a no-op.
            let resumer = ResumeGuard()
            let resolve: @Sendable (Result<ProcessResult, Error>) -> Void = { result in
                resumer.tryResume {
                    continuation.resume(with: result)
                }
            }

            process.terminationHandler = { proc in
                resolve(.success(ProcessResult(
                    exitCode: proc.terminationStatus,
                    stdout: Self.readPipe(stdoutPipe),
                    stderr: Self.readPipe(stderrPipe)
                )))
            }

            do {
                try process.run()
                if let stdin, let stdinPipe = process.standardInput as? Pipe {
                    stdinPipe.fileHandleForWriting.write(stdin.data(using: .utf8) ?? Data())
                    try? stdinPipe.fileHandleForWriting.close()
                }
            } catch {
                resolve(.failure(error))
                return
            }

            // Schedule the kill-switch on a detached task; the termination
            // handler races it for the resume.
            Task {
                try? await Task.sleep(for: .seconds(timeout))
                if process.isRunning {
                    process.terminate()
                }
            }
        }
    }

    /// Build an environment dict with PATH widened to cover the locations
    /// users actually install CLI tools at. Order matches the typical
    /// shell PATH on macOS:
    ///
    /// - `/opt/homebrew/bin` — Apple Silicon Homebrew
    /// - `/usr/local/bin` — Intel Homebrew + manual installs
    /// - `~/.local/bin` — pipx, cargo, etc.
    /// - inherited PATH (whatever the GUI launch gave us)
    /// - fallback `/usr/bin:/bin:/usr/sbin:/sbin`
    static func augmentedEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let inherited = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        let home = env["HOME"] ?? NSHomeDirectory()
        let extras = [
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "/usr/local/sbin",
            "\(home)/.local/bin",
            "\(home)/.cargo/bin",
        ]
        let inheritedComponents = inherited.split(separator: ":").map(String.init)
        var seen = Set<String>()
        var ordered: [String] = []
        for path in extras + inheritedComponents {
            guard !path.isEmpty, !seen.contains(path) else { continue }
            seen.insert(path)
            ordered.append(path)
        }
        env["PATH"] = ordered.joined(separator: ":")
        return env
    }

    private static func readPipe(_ pipe: Pipe) -> String {
        do {
            if let data = try pipe.fileHandleForReading.readToEnd() {
                return String(data: data, encoding: .utf8) ?? ""
            }
        } catch {
            // Best-effort: empty stdout/stderr beats leaking a confusing
            // exception message to the HUD.
        }
        return ""
    }
}

/// Thread-safe single-shot guard so termination + timeout race resolvers
/// can both call without double-resuming the continuation.
private final class ResumeGuard: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false

    func tryResume(_ block: () -> Void) {
        lock.lock()
        let alreadyResumed = resumed
        if !alreadyResumed {
            resumed = true
        }
        lock.unlock()

        if !alreadyResumed {
            block()
        }
    }
}

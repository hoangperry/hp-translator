import AppKit
import Foundation

/// Records the frontmost application PID at hotkey-press time and lets the
/// translation workflow verify focus has not changed before injecting any
/// keystrokes (`Cmd+V` paste, `Return` send).
///
/// Closes security finding F-5: synthetic keystrokes landing in the wrong
/// app when the user `Cmd-Tab`s away during the LLM round-trip.
@MainActor
final class FocusGuard {
    /// Closure-based seam so tests can inject deterministic frontmost PIDs.
    private let frontmostPID: () -> pid_t?

    private var capturedPID: pid_t?

    init(frontmostPID: @escaping () -> pid_t? = { NSWorkspace.shared.frontmostApplication?.processIdentifier }) {
        self.frontmostPID = frontmostPID
    }

    /// Record the current frontmost-app PID. Call at the start of any
    /// workflow that may inject keystrokes after an asynchronous step.
    func capture() {
        capturedPID = frontmostPID()
    }

    /// Returns `true` when (a) a capture has been performed, (b) the current
    /// frontmost PID matches the captured value. Returns `false` otherwise —
    /// the workflow must abort to avoid mis-targeted keystrokes.
    func isStillFocused() -> Bool {
        guard let captured = capturedPID, let current = frontmostPID() else {
            return false
        }
        return captured == current
    }

    /// Allows a short grace period before declaring focus lost. This absorbs
    /// brief frontmost-app flickers from system UI while still failing closed.
    func isStillFocused(
        afterGrace grace: Duration,
        sleep: @MainActor (Duration) async -> Void = { duration in
            try? await Task.sleep(for: duration)
        }
    ) async -> Bool {
        if isStillFocused() {
            return true
        }

        await sleep(grace)
        return isStillFocused()
    }

    /// Convenience for tests / diagnostics.
    var capturedProcessIdentifier: pid_t? { capturedPID }
}

import Foundation
import Testing

@testable import ContextualMacTranslator

@Suite("FocusGuard")
@MainActor
struct FocusGuardTests {
    @Test("captures and matches the same frontmost PID")
    func sameFrontmostMatches() {
        var pid: pid_t = 4242
        let guardian = FocusGuard(frontmostPID: { pid })
        guardian.capture()
        #expect(guardian.isStillFocused() == true)

        // Even if PID stays the same across long async operations:
        pid = 4242
        #expect(guardian.isStillFocused() == true)
    }

    @Test("detects PID change as focus loss")
    func pidChangeIsAbort() {
        var pid: pid_t = 100
        let guardian = FocusGuard(frontmostPID: { pid })
        guardian.capture()
        #expect(guardian.isStillFocused() == true)

        pid = 200 // simulating Cmd-Tab to another app
        #expect(guardian.isStillFocused() == false)
    }

    @Test("returns false when frontmost is unknown (nil PID)")
    func unknownFrontmostFailsClosed() {
        var pid: pid_t? = 5
        let guardian = FocusGuard(frontmostPID: { pid })
        guardian.capture()

        pid = nil
        #expect(guardian.isStillFocused() == false)
    }

    @Test("returns false if no capture was performed")
    func mustCaptureFirst() {
        let guardian = FocusGuard(frontmostPID: { 1 })
        // No capture() call.
        #expect(guardian.isStillFocused() == false)
    }

    @Test("re-capture overrides earlier capture")
    func recaptureUpdates() {
        var pid: pid_t = 10
        let guardian = FocusGuard(frontmostPID: { pid })
        guardian.capture()
        pid = 20
        guardian.capture() // user reset focus reading
        #expect(guardian.isStillFocused() == true)

        pid = 30
        #expect(guardian.isStillFocused() == false)
    }

    @Test("short focus flicker can recover inside grace period")
    func graceAllowsRecoveredFocus() async {
        var pid: pid_t = 10
        let guardian = FocusGuard(frontmostPID: { pid })
        guardian.capture()

        pid = 20
        let result = await guardian.isStillFocused(afterGrace: .milliseconds(250)) { _ in
            pid = 10
        }

        #expect(result == true)
    }

    @Test("grace still fails closed when focus remains changed")
    func graceFailsClosedWhenFocusStaysChanged() async {
        var pid: pid_t = 10
        let guardian = FocusGuard(frontmostPID: { pid })
        guardian.capture()

        pid = 20
        let result = await guardian.isStillFocused(afterGrace: .milliseconds(250)) { _ in }

        #expect(result == false)
    }
}

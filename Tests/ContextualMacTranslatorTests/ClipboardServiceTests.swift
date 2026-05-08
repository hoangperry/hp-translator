import Foundation
import Testing

@testable import ContextualMacTranslator

@Suite("ClipboardService.pollForChange")
@MainActor
struct ClipboardPollTests {
    /// Counter helper that flips after N polls.
    final class CountSequence: @unchecked Sendable {
        private var values: [Int]
        private var index = 0
        init(_ values: [Int]) { self.values = values }
        func next() -> Int {
            defer { if index < values.count - 1 { index += 1 } }
            return values[index]
        }
    }

    @Test("returns nil when changeCount never advances (stale clipboard fix)")
    func staleClipboardReturnsNil() async {
        let result = await ClipboardService.pollForChange(
            previousChangeCount: 100,
            currentChangeCount: { 100 }, // never changes
            currentString: { "STALE PASSWORD" }, // attacker bait — must not return this
            timeout: .milliseconds(60),
            sleep: { _ in }
        )
        #expect(result == nil)
    }

    @Test("returns new string when changeCount advances and content is non-empty")
    func returnsCopiedText() async {
        let counts = CountSequence([100, 100, 101]) // advances on 3rd poll
        let result = await ClipboardService.pollForChange(
            previousChangeCount: 100,
            currentChangeCount: { counts.next() },
            currentString: { "the user's selected text" },
            timeout: .milliseconds(200),
            sleep: { _ in }
        )
        #expect(result == "the user's selected text")
    }

    @Test("returns nil when changeCount advanced but content is whitespace only")
    func ignoresWhitespaceOnly() async {
        let counts = CountSequence([100, 101])
        let result = await ClipboardService.pollForChange(
            previousChangeCount: 100,
            currentChangeCount: { counts.next() },
            currentString: { "   \n  " },
            timeout: .milliseconds(60),
            sleep: { _ in }
        )
        #expect(result == nil)
    }

    @Test("returns nil if changeCount never advances even after timeout")
    func timeoutWithoutChangeReturnsNil() async {
        let result = await ClipboardService.pollForChange(
            previousChangeCount: 5,
            currentChangeCount: { 5 },
            currentString: { "leftover from yesterday" },
            timeout: .milliseconds(40),
            sleep: { _ in }
        )
        #expect(result == nil)
    }
}

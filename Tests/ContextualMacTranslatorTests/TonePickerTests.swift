import Carbon.HIToolbox
import Foundation
import Testing

@testable import ContextualMacTranslator

@Suite("PickerPanel key routing")
struct PickerPanelKeyRoutingTests {
    @Test("Esc maps to escape")
    func mapEsc() {
        #expect(PickerPanel.map(keyCode: kVK_Escape, withCommand: false) == .escape)
    }

    @Test("Return + keypad-enter both map to return")
    func mapReturn() {
        #expect(PickerPanel.map(keyCode: kVK_Return, withCommand: false) == .return)
        #expect(PickerPanel.map(keyCode: kVK_ANSI_KeypadEnter, withCommand: false) == .return)
    }

    @Test("Arrows map regardless of command flag")
    func mapArrows() {
        #expect(PickerPanel.map(keyCode: kVK_DownArrow, withCommand: false) == .arrowDown)
        #expect(PickerPanel.map(keyCode: kVK_UpArrow, withCommand: false) == .arrowUp)
        #expect(PickerPanel.map(keyCode: kVK_DownArrow, withCommand: true) == .arrowDown)
    }

    @Test("⌘+digit maps to .digit; bare digit is passed through")
    func mapDigits() {
        #expect(PickerPanel.map(keyCode: kVK_ANSI_1, withCommand: true) == .digit(1))
        #expect(PickerPanel.map(keyCode: kVK_ANSI_7, withCommand: true) == .digit(7))
        // Bare digits must NOT be intercepted — they flow through to the
        // SwiftUI TextField for type-to-filter.
        #expect(PickerPanel.map(keyCode: kVK_ANSI_1, withCommand: false) == nil)
        #expect(PickerPanel.map(keyCode: kVK_ANSI_5, withCommand: false) == nil)
    }

    @Test("Unknown keycodes are not intercepted")
    func mapUnknown() {
        // Letter A — must pass through for type-to-filter.
        #expect(PickerPanel.map(keyCode: kVK_ANSI_A, withCommand: false) == nil)
        #expect(PickerPanel.map(keyCode: kVK_Space, withCommand: false) == nil)
        // ⌘+letter is also not a picker hotkey — pass through.
        #expect(PickerPanel.map(keyCode: kVK_ANSI_A, withCommand: true) == nil)
    }
}

@Suite("TonePickerViewModel")
@MainActor
struct TonePickerViewModelTests {
    private func makeModel() -> (TonePickerViewModel, Box<RewriteTone??>) {
        let model = TonePickerViewModel()
        let box = Box<RewriteTone??>(nil)
        model.onCommit = { tone in box.value = .some(tone) }
        return (model, box)
    }

    @Test("filtered defaults to all items when query is empty")
    func filteredDefault() {
        let (model, _) = makeModel()
        #expect(model.filtered == RewriteTone.allCases)
    }

    @Test("filter is case-insensitive substring on displayName")
    func filterSubstring() {
        let (model, _) = makeModel()
        model.query = "pro"
        #expect(model.filtered == [.professional])
        // "poli" matches BOTH "Polite" and "Firm but polite" — keep both.
        model.query = "  PoLi  "
        #expect(model.filtered == [.polite, .firmButPolite])
    }

    @Test("Empty filter result")
    func filterMiss() {
        let (model, _) = makeModel()
        model.query = "zzzzz"
        #expect(model.filtered.isEmpty)
    }

    @Test("Escape commits nil")
    func escCommitsNil() {
        let (model, box) = makeModel()
        _ = model.handle(.escape)
        #expect(box.value == .some(nil))
        #expect(model.resolved)
    }

    @Test("Return commits the selected tone")
    func returnCommitsSelection() {
        let (model, box) = makeModel()
        model.selection = 2  // .friendly
        _ = model.handle(.return)
        #expect(box.value == .some(.friendly))
    }

    @Test("Return with empty filter commits nil")
    func returnEmptyFilterCommitsNil() {
        let (model, box) = makeModel()
        model.query = "zzzzz"
        _ = model.handle(.return)
        #expect(box.value == .some(nil))
    }

    @Test("Arrow down cycles selection")
    func arrowDownCycles() {
        let (model, _) = makeModel()
        let count = RewriteTone.allCases.count
        for i in 1..<count {
            _ = model.handle(.arrowDown)
            #expect(model.selection == i)
        }
        // Wraps around back to 0.
        _ = model.handle(.arrowDown)
        #expect(model.selection == 0)
    }

    @Test("Arrow up cycles selection backwards")
    func arrowUpCycles() {
        let (model, _) = makeModel()
        _ = model.handle(.arrowUp)
        #expect(model.selection == RewriteTone.allCases.count - 1)
    }

    @Test("⌘+digit commits that index directly")
    func digitCommits() {
        let (model, box) = makeModel()
        _ = model.handle(.digit(1))
        #expect(box.value == .some(RewriteTone.allCases[0]))
    }

    @Test("⌘+digit past the filtered list is silently consumed")
    func digitOutOfRangeNoOp() {
        let (model, box) = makeModel()
        _ = model.handle(.digit(99))
        #expect(box.value == nil)   // no commit happened
        #expect(!model.resolved)
    }

    @Test("commit is idempotent — second call is a no-op")
    func commitIdempotent() {
        let (model, box) = makeModel()
        model.commit(.polite)
        model.commit(.professional)   // should be ignored
        #expect(box.value == .some(.polite))
    }

    @Test("clampSelectionAfterFilter pulls selection in range")
    func clampSelection() {
        let (model, _) = makeModel()
        model.selection = 99
        model.clampSelectionAfterFilter()
        #expect(model.selection == RewriteTone.allCases.count - 1)

        model.query = "zzzzz"   // filtered = empty
        model.clampSelectionAfterFilter()
        #expect(model.selection == 0)
    }
}

/// Minimal mutable box so tests can capture the commit value out of a
/// closure without race conditions. `@MainActor` callers only.
@MainActor
private final class Box<T> {
    var value: T
    init(_ value: T) { self.value = value }
}

@Suite("Focused element role classification")
struct FocusedElementInspectorTests {
    @Test("Text input roles all map to textInput")
    func mapTextRoles() {
        for role in ["AXTextField", "AXTextArea", "AXComboBox"] {
            #expect(FocusedElementInspector.kind(forRole: role) == .textInput)
        }
    }

    @Test("Secure text field maps to secureTextInput")
    func mapSecureRole() {
        #expect(FocusedElementInspector.kind(forRole: "AXSecureTextField") == .secureTextInput)
    }

    @Test("Unrelated roles map to other")
    func mapOtherRoles() {
        for role in ["AXButton", "AXMenuItem", "AXStaticText", "AXImage", "", "AXTextFieldX"] {
            #expect(FocusedElementInspector.kind(forRole: role) == .other)
        }
    }
}

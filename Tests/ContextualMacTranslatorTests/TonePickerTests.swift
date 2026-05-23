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
    private func makeModel() -> (TonePickerViewModel, Box<PickerEntry??>) {
        let model = TonePickerViewModel()
        let box = Box<PickerEntry??>(nil)
        model.onCommit = { entry in box.value = .some(entry) }
        return (model, box)
    }

    @Test("entries default to all presets when query is empty")
    func entriesDefault() {
        let (model, _) = makeModel()
        let expected = RewriteTone.allCases.map(PickerEntry.preset)
        #expect(model.entries == expected)
    }

    @Test("Typing prepends a freetext entry above filtered presets")
    func entriesWithFreetext() {
        let (model, _) = makeModel()
        model.query = "pro"
        #expect(model.entries == [.freetext("pro"), .preset(.professional)])
        model.query = "  PoLi  "
        // freetext is trimmed; both Polite and Firm-but-polite match.
        #expect(model.entries == [.freetext("PoLi"), .preset(.polite), .preset(.firmButPolite)])
    }

    @Test("Filter miss still keeps the freetext entry")
    func entriesFilterMiss() {
        let (model, _) = makeModel()
        model.query = "zzzzz"
        #expect(model.entries == [.freetext("zzzzz")])
    }

    @Test("Escape commits nil")
    func escCommitsNil() {
        let (model, box) = makeModel()
        _ = model.handle(.escape)
        #expect(box.value == .some(nil))
        #expect(model.resolved)
    }

    @Test("Return commits the selected preset")
    func returnCommitsSelection() {
        let (model, box) = makeModel()
        model.selection = 2  // .friendly (no query → entries are presets only)
        _ = model.handle(.return)
        #expect(box.value == .some(.preset(.friendly)))
    }

    @Test("Return on the freetext row commits the typed instruction")
    func returnCommitsFreetext() {
        let (model, box) = makeModel()
        model.query = "make it sound less defensive"
        model.selection = 0  // top row = freetext
        _ = model.handle(.return)
        #expect(box.value == .some(.freetext("make it sound less defensive")))
    }

    @Test("Arrow down cycles selection")
    func arrowDownCycles() {
        let (model, _) = makeModel()
        let count = RewriteTone.allCases.count   // entries with empty query
        for i in 1..<count {
            _ = model.handle(.arrowDown)
            #expect(model.selection == i)
        }
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
        // No query → entries[0] is the first preset.
        #expect(box.value == .some(.preset(RewriteTone.allCases[0])))
    }

    @Test("⌘+1 with a query commits the freetext row at index 0")
    func digitOneSelectsFreetext() {
        let (model, box) = makeModel()
        model.query = "shorter"
        _ = model.handle(.digit(1))
        #expect(box.value == .some(.freetext("shorter")))
    }

    @Test("⌘+digit past the entry list is silently consumed")
    func digitOutOfRangeNoOp() {
        let (model, box) = makeModel()
        _ = model.handle(.digit(99))
        #expect(box.value == nil)
        #expect(!model.resolved)
    }

    @Test("commit is idempotent — second call is a no-op")
    func commitIdempotent() {
        let (model, box) = makeModel()
        model.commit(.preset(.polite))
        model.commit(.preset(.professional))
        #expect(box.value == .some(.preset(.polite)))
    }

    // MARK: - v0.8.4 — Bindings surfaced in the picker

    /// Helper: a binding rigged with a custom hotkey + instruction so
    /// the assertion is unambiguous about *which* binding came back.
    private func makeBinding(
        tone: RewriteTone = .professional,
        instruction: String = "Sound like a TPM with deadlines"
    ) -> RewriteBinding {
        RewriteBinding(
            tone: tone,
            customInstruction: instruction,
            hotkey: HotkeyConfig(keyCode: kVK_ANSI_R, modifiers: controlKey | optionKey)
        )
    }

    @Test("bindings append below presets and are visible by default")
    func bindingsAppearAfterPresets() {
        let binding = makeBinding()
        let model = TonePickerViewModel(bindings: [binding])
        let entries = model.entries
        // Presets first, then the binding.
        #expect(entries.count == RewriteTone.allCases.count + 1)
        #expect(entries.last == .binding(binding))
    }

    @Test("query filters bindings by displayName too")
    func queryFiltersBindings() {
        let pro = makeBinding(tone: .professional, instruction: "tpm")
        let casual = RewriteBinding(
            tone: .friendly,
            customInstruction: "warm",
            hotkey: HotkeyConfig(keyCode: kVK_ANSI_F, modifiers: controlKey)
        )
        let model = TonePickerViewModel(bindings: [pro, casual])
        model.query = "pro"
        let entries = model.entries
        // freetext "pro" + .professional preset + the .professional binding
        // (the friendly binding is filtered out since its label has no "pro")
        #expect(entries.contains(.binding(pro)))
        #expect(!entries.contains(.binding(casual)))
    }

    @Test("⌘+digit can commit a binding row")
    func digitSelectsBinding() {
        let binding = makeBinding()
        let model = TonePickerViewModel(bindings: [binding])
        let box = Box<PickerEntry??>(nil)
        model.onCommit = { box.value = .some($0) }
        let bindingIndex = model.entries.firstIndex(of: .binding(binding))!
        _ = model.handle(.digit(bindingIndex + 1))
        #expect(box.value == .some(.binding(binding)))
    }
}

@Suite("RewriteBinding v0.8.4 fields")
struct RewriteBindingV084Tests {
    @Test("showInPicker defaults to true for new bindings")
    func defaultsToTrue() {
        let b = RewriteBinding(
            tone: .polite,
            hotkey: HotkeyConfig(keyCode: kVK_ANSI_P, modifiers: optionKey)
        )
        #expect(b.showInPicker == true)
    }

    @Test("legacy persisted JSON (pre-v0.8.4) decodes with showInPicker=true")
    func legacyDecodeDefaultsToTrue() throws {
        // No `showInPicker` key — what v0.8.3 wrote to disk.
        // modifiers is a UInt32 Carbon mask (here: optionKey = 2048).
        let legacyJSON = """
        {
          "id": "F47AC10B-58CC-4372-A567-0E02B2C3D479",
          "tone": "polite",
          "customInstruction": "",
          "hotkey": { "keyCode": 35, "modifiers": 2048 }
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(RewriteBinding.self, from: legacyJSON)
        #expect(decoded.showInPicker == true)
        #expect(decoded.tone == .polite)
    }

    @Test("explicit false survives a round-trip through Codable")
    func roundtripFalse() throws {
        let original = RewriteBinding(
            tone: .friendly,
            hotkey: HotkeyConfig(keyCode: kVK_ANSI_F, modifiers: controlKey),
            showInPicker: false
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RewriteBinding.self, from: data)
        #expect(decoded.showInPicker == false)
        #expect(decoded == original)
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

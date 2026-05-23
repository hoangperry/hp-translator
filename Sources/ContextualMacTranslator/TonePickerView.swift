import AppKit
import Carbon.HIToolbox
import Observation
import SwiftUI

/// One of the hard keys the picker panel intercepts before the SwiftUI
/// TextField has a chance to see them. Plain text characters (including
/// bare digits) flow through to SwiftUI for type-to-filter.
enum PickerKey: Sendable, Equatable {
    case escape
    case `return`
    case arrowUp
    case arrowDown
    case digit(Int)   // 1...9 (paired with ⌘ in `keyDown`)
}

/// One row in the picker. Three flavours:
///   • `.freetext` — the user's typed instruction as a virtual top row
///     ("Use: …") when they're typing.
///   • `.preset`   — a built-in `RewriteTone`.
///   • `.binding`  — one of the user's persisted `RewriteBinding`s
///     surfaced in the picker (v0.8.4) so they can pick a saved
///     instruction without remembering its hotkey.
enum PickerEntry: Equatable, Sendable, Identifiable {
    case freetext(String)
    case preset(RewriteTone)
    case binding(RewriteBinding)

    var id: String {
        switch self {
        case .freetext:          return "__freetext__"
        case .preset(let tone):  return "preset:" + tone.rawValue
        case .binding(let b):    return "binding:" + b.id.uuidString
        }
    }

    /// Label used by the row + the HUD persona badge.
    var displayName: String {
        switch self {
        case .freetext(let text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let snippet = trimmed.count > 40
                ? String(trimmed.prefix(40)) + "…"
                : trimmed
            return "Use: \"\(snippet)\""
        case .preset(let tone):
            return tone.displayName
        case .binding(let binding):
            return binding.displayName
        }
    }
}

/// `NSPanel` subclass for the tone picker — same `.nonactivatingPanel`
/// shape as `KeyableNonactivatingPanel` (PreviewHUD) but with richer key
/// routing. `onKey` returns `true` when it consumed the event so we know
/// whether to call `super.keyDown` (which would forward text to the
/// SwiftUI TextField for filtering).
final class PickerPanel: NSPanel {
    var onKey: ((PickerKey) -> Bool)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        let code = Int(event.keyCode)
        let withCommand = event.modifierFlags.contains(.command)
        let key: PickerKey? = Self.map(keyCode: code, withCommand: withCommand)
        if let key, onKey?(key) == true {
            return   // consumed — don't bubble to TextField
        }
        super.keyDown(with: event)
    }

    /// Pure mapping from a Carbon keyCode (+ command flag) to a `PickerKey`.
    /// Factored out so tests can verify the routing without an NSEvent.
    static func map(keyCode: Int, withCommand: Bool) -> PickerKey? {
        switch keyCode {
        case kVK_Escape:               return .escape
        case kVK_Return, kVK_ANSI_KeypadEnter: return .return
        case kVK_DownArrow:            return .arrowDown
        case kVK_UpArrow:              return .arrowUp
        default:
            guard withCommand, let n = digit(forKeyCode: keyCode) else { return nil }
            return .digit(n)
        }
    }

    private static func digit(forKeyCode code: Int) -> Int? {
        switch code {
        case kVK_ANSI_1: return 1
        case kVK_ANSI_2: return 2
        case kVK_ANSI_3: return 3
        case kVK_ANSI_4: return 4
        case kVK_ANSI_5: return 5
        case kVK_ANSI_6: return 6
        case kVK_ANSI_7: return 7
        case kVK_ANSI_8: return 8
        case kVK_ANSI_9: return 9
        default:         return nil
        }
    }
}

// MARK: - View model

/// View model backing the tone picker. Owns the filter query, the
/// highlight selection, and the commit lifecycle. `resolved` makes
/// commit idempotent so a double-Return (e.g. picker re-press while
/// open) cannot resolve the continuation twice.
@MainActor
@Observable
final class TonePickerViewModel {
    let items: [RewriteTone]
    let bindings: [RewriteBinding]
    var query: String = ""
    var selection: Int = 0
    private(set) var resolved: Bool = false

    var onCommit: (PickerEntry?) -> Void = { _ in }

    init(
        items: [RewriteTone] = RewriteTone.allCases,
        bindings: [RewriteBinding] = []
    ) {
        self.items = items
        self.bindings = bindings
    }

    /// All visible rows in order: optional freetext (when query non-empty)
    /// → filtered presets → filtered bindings. Filter is case-insensitive
    /// substring on the displayed label.
    var entries: [PickerEntry] {
        let raw = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = raw.lowercased()
        var rows: [PickerEntry] = []
        if !raw.isEmpty {
            rows.append(.freetext(raw))
        }
        for tone in items where lowered.isEmpty || tone.displayName.lowercased().contains(lowered) {
            rows.append(.preset(tone))
        }
        for binding in bindings where lowered.isEmpty || binding.displayName.lowercased().contains(lowered) {
            rows.append(.binding(binding))
        }
        return rows
    }

    /// Hard-key handler. Returns `true` when the key was consumed; the
    /// panel uses that to suppress further propagation.
    func handle(_ key: PickerKey) -> Bool {
        switch key {
        case .escape:
            commit(nil)
            return true
        case .return:
            let list = entries
            if list.indices.contains(selection) {
                commit(list[selection])
            } else {
                commit(nil)
            }
            return true
        case .arrowDown:
            let list = entries
            guard !list.isEmpty else { return true }
            selection = (selection + 1) % list.count
            return true
        case .arrowUp:
            let list = entries
            guard !list.isEmpty else { return true }
            selection = (selection - 1 + list.count) % list.count
            return true
        case .digit(let n):
            let list = entries
            let idx = n - 1
            if list.indices.contains(idx) {
                commit(list[idx])
            }
            // Out-of-range digit is silently consumed — no flicker, no
            // accidental commit, no system beep.
            return true
        }
    }

    /// Idempotent commit. Subsequent calls are no-ops so the panel can
    /// fire close() from multiple paths (Esc, click-outside, focus loss)
    /// without double-resuming the continuation.
    func commit(_ entry: PickerEntry?) {
        guard !resolved else { return }
        resolved = true
        onCommit(entry)
    }
}

// MARK: - View

struct TonePickerView: View {
    @Bindable var model: TonePickerViewModel
    @FocusState private var filterFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "wand.and.sparkles")
                    .foregroundStyle(.secondary)
                TextField("Filter or describe…", text: $model.query)
                    .textFieldStyle(.plain)
                    .focused($filterFocused)
                    .onChange(of: model.query) { _, _ in
                        // Reset highlight when the filter changes so the
                        // top entry is auto-selected — that's the
                        // "Use custom: …" row if the user typed.
                        model.selection = 0
                    }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider().opacity(0.4)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        let list = model.entries
                        if list.isEmpty {
                            Text("No matching tones")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 18)
                        } else {
                            ForEach(Array(list.enumerated()), id: \.element.id) { idx, entry in
                                TonePickerRow(
                                    entry: entry,
                                    index: idx,
                                    selected: idx == model.selection
                                )
                                .id(entry.id)
                                .contentShape(Rectangle())
                                .onTapGesture { model.commit(entry) }
                                .onHover { hovering in
                                    if hovering { model.selection = idx }
                                }
                            }
                        }
                    }
                    .padding(6)
                }
                .onChange(of: model.selection) { _, _ in
                    let list = model.entries
                    if list.indices.contains(model.selection) {
                        withAnimation(.snappy(duration: 0.12)) {
                            proxy.scrollTo(list[model.selection].id, anchor: .center)
                        }
                    }
                }
            }
        }
        .frame(width: 360, height: 340)
        .liquidGlassBackground(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.separator.opacity(0.6), lineWidth: 0.5)
        )
        // v0.8.4 — VoiceOver: announce the popup as a labelled container
        // and auto-focus the filter field on open so VO + keyboard users
        // can immediately type.
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tone picker")
        .accessibilityHint("Type to filter, arrow keys to navigate, Return to apply, Escape to cancel")
        .onAppear { filterFocused = true }
    }
}

private struct TonePickerRow: View {
    let entry: PickerEntry
    let index: Int
    let selected: Bool

    var body: some View {
        HStack(spacing: 10) {
            if case .freetext = entry {
                Image(systemName: "pencil.line")
                    .foregroundStyle(.secondary)
            }
            Text(entry.displayName)
                .font(.body)
                .italic(isFreetext)
                .foregroundStyle(isFreetext ? AnyShapeStyle(.primary) : AnyShapeStyle(.primary))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            if index < 9 {
                Text("⌘\(index + 1)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            selected ? AnyShapeStyle(.tint.opacity(0.20)) : AnyShapeStyle(.clear),
            in: RoundedRectangle(cornerRadius: 8)
        )
        // v0.8.4 — accessibility: VoiceOver should announce each row as
        // a single button with a meaningful label + ⌘-shortcut hint, and
        // call out selection state so users navigating with VO arrows
        // hear which row is highlighted.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.displayName)
        .accessibilityHint(index < 9 ? "Command \(index + 1) to choose" : "")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private var isFreetext: Bool {
        if case .freetext = entry { return true }
        return false
    }
}

import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Sheet that captures the next key combination the user presses and
/// returns it as a `HotkeyConfig`. Validates that at least one modifier
/// is held (otherwise the recorded hotkey would conflict with normal
/// typing). Surfaces a conflict warning when the captured combo is
/// already bound elsewhere in `SettingsStore`.
@MainActor
struct HotkeyRecorderSheet: View {
    @Binding var hotkey: HotkeyConfig
    @Binding var isPresented: Bool
    /// Optional ID of the binding currently being edited; conflict check
    /// excludes it so users can re-confirm the existing hotkey without
    /// false alarm.
    var ownerBindingID: UUID?

    @ObservedObject private var settings = SettingsStore.shared

    @State private var capturedHotkey: HotkeyConfig?
    @State private var status: RecorderStatus = .waiting

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Record hotkey")
                .font(.headline)
            Text("Press the key combination you want to bind. Hold at least one modifier (⌘, ⌥, ⌃, or ⇧) plus one regular key. Press Esc to cancel.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HotkeyCaptureView { config in
                handleCapture(config)
            } onEscape: {
                isPresented = false
            }
            .frame(height: 80)
            .frame(maxWidth: .infinity)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(.separator, lineWidth: 1)
            )
            .overlay(
                Text(captureLabel)
                    .font(.system(.title3, design: .monospaced))
                    .foregroundStyle(.primary)
            )

            statusView

            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    if let captured = capturedHotkey {
                        hotkey = captured
                    }
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(capturedHotkey == nil || status.isError)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private var captureLabel: String {
        capturedHotkey?.displayLabel ?? "Press a hotkey…"
    }

    @ViewBuilder
    private var statusView: some View {
        switch status {
        case .waiting:
            Label("Waiting for key press", systemImage: "keyboard")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .needsModifier:
            Label("Hotkey needs at least one modifier (⌘/⌥/⌃/⇧).", systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
        case .conflict(let label):
            Label("This combo is already bound to: \(label).", systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
        case .ready:
            Label("Looks good. Press Save to apply.", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        }
    }

    private func handleCapture(_ config: HotkeyConfig) {
        // Hotkey must include a non-modifier key + at least one modifier.
        let hasModifier = config.modifiers != 0
        guard hasModifier else {
            status = .needsModifier
            capturedHotkey = nil
            return
        }
        capturedHotkey = config
        if let conflictLabel = settings.bindingLabel(usingHotkey: config, excluding: ownerBindingID) {
            status = .conflict(conflictLabel)
        } else {
            status = .ready
        }
    }

    enum RecorderStatus: Equatable {
        case waiting
        case needsModifier
        case conflict(String)
        case ready

        var isError: Bool {
            switch self {
            case .needsModifier, .conflict:
                return true
            case .waiting, .ready:
                return false
            }
        }
    }
}

/// SwiftUI wrapper around an NSView that owns the first responder and
/// translates incoming `keyDown` events into `HotkeyConfig`s. Stays
/// first-responder while visible so Tab / arrow keys are also captured.
@MainActor
struct HotkeyCaptureView: NSViewRepresentable {
    let onCapture: (HotkeyConfig) -> Void
    let onEscape: () -> Void

    func makeNSView(context: Context) -> KeyCaptureView {
        let view = KeyCaptureView()
        view.onCapture = onCapture
        view.onEscape = onEscape
        return view
    }

    func updateNSView(_ view: KeyCaptureView, context: Context) {
        view.onCapture = onCapture
        view.onEscape = onEscape
    }
}

/// First-responder NSView that swallows every `keyDown` and reports the
/// captured (keyCode, modifiers) pair. Modifier-only presses are ignored
/// (caller validates we got a non-modifier key too).
final class KeyCaptureView: NSView {
    var onCapture: ((HotkeyConfig) -> Void)?
    var onEscape: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in
            self?.window?.makeFirstResponder(self)
        }
    }

    override func keyDown(with event: NSEvent) {
        // Esc cancels the recorder.
        if Int(event.keyCode) == kVK_Escape {
            onEscape?()
            return
        }
        let modifiers = Self.carbonModifiers(from: event.modifierFlags)
        let config = HotkeyConfig(keyCode: UInt32(event.keyCode), modifiers: modifiers)
        onCapture?(config)
    }

    /// Map Cocoa's `NSEvent.ModifierFlags` to Carbon's modifier mask
    /// expected by `RegisterEventHotKey`.
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var carbon: UInt32 = 0
        let mask = flags.intersection(.deviceIndependentFlagsMask)
        if mask.contains(.command)  { carbon |= UInt32(cmdKey) }
        if mask.contains(.option)   { carbon |= UInt32(optionKey) }
        if mask.contains(.control)  { carbon |= UInt32(controlKey) }
        if mask.contains(.shift)    { carbon |= UInt32(shiftKey) }
        return carbon
    }
}

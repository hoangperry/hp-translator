import AppKit
import Observation
import SwiftUI

/// User decision returned from the preview HUD.
enum PreviewDecision: Equatable, Sendable {
    case send(String)   // user accepted the (possibly edited) translation
    case cancel
}

/// Protocol so `TranslationWorkflow` can be tested with a stubbed preview UI.
@MainActor
protocol PreviewPresenter: AnyObject {
    func presentPreview(
        original: String,
        translated: String,
        persona: Persona,
        isSourceFocused: @escaping @MainActor () -> Bool
    ) async -> PreviewDecision

    /// v0.8.5 — multi-variant entry point. `variants` MUST contain at
    /// least one entry; presenters page through them with ← → arrows or
    /// ⌘1-N quick-select. The decision returns the user-confirmed
    /// (possibly edited) text of the *selected* variant.
    func presentVariants(
        original: String,
        variants: [String],
        persona: Persona,
        isSourceFocused: @escaping @MainActor () -> Bool
    ) async -> PreviewDecision
}

extension PreviewPresenter {
    /// Default adapter — single-variant flow is just `presentVariants`
    /// with a one-element list. Lets existing stubs / tests that only
    /// implement `presentPreview` opt-in to multi-variant later.
    func presentVariants(
        original: String,
        variants: [String],
        persona: Persona,
        isSourceFocused: @escaping @MainActor () -> Bool
    ) async -> PreviewDecision {
        let translated = variants.first ?? ""
        return await presentPreview(
            original: original,
            translated: translated,
            persona: persona,
            isSourceFocused: isSourceFocused
        )
    }
}

/// `NSPanel` subclass that can become key — required so SwiftUI's
/// `keyboardShortcut(.defaultAction / .cancelAction)` modifiers fire on
/// `Return` / `Esc`. Combined with `.nonactivatingPanel`, the panel becomes
/// key without bringing the entire app forward, preserving focus on the
/// original target app for the subsequent paste.
final class KeyableNonactivatingPanel: NSPanel {
    var onTabPressed: (() -> Void)?
    /// v0.8.5 — ← / → navigate between variants (when present). ⌘1–5
    /// quick-select a variant by ordinal. Routed to the view-model via
    /// these closures so SwiftUI doesn't have to wire ResponderChain.
    var onLeftArrowPressed: (() -> Void)?
    var onRightArrowPressed: (() -> Void)?
    var onCommandDigitPressed: ((Int) -> Void)?

    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 48 {
            onTabPressed?()
            return
        }
        // Carbon keyCodes — ← 123, → 124.
        if event.keyCode == 123, !event.modifierFlags.contains(.command) {
            onLeftArrowPressed?()
            return
        }
        if event.keyCode == 124, !event.modifierFlags.contains(.command) {
            onRightArrowPressed?()
            return
        }
        if event.modifierFlags.contains(.command),
           let chars = event.charactersIgnoringModifiers,
           let n = chars.first?.wholeNumberValue,
           (1...5).contains(n) {
            onCommandDigitPressed?(n)
            return
        }
        super.keyDown(with: event)
    }
}

/// Real preview HUD: floating NSPanel + SwiftUI body with persona badge.
@MainActor
final class PreviewHUDController: PreviewPresenter {
    private var panel: KeyableNonactivatingPanel?
    private var hostingController: NSHostingController<PreviewHUDView>?
    private var focusMonitorTask: Task<Void, Never>?

    private let focusLossTimeout: Duration
    private let focusPollInterval: Duration

    init(
        focusLossTimeout: Duration = .seconds(5),
        focusPollInterval: Duration = .milliseconds(250)
    ) {
        self.focusLossTimeout = focusLossTimeout
        self.focusPollInterval = focusPollInterval
    }

    func presentPreview(
        original: String,
        translated: String,
        persona: Persona,
        isSourceFocused: @escaping @MainActor () -> Bool
    ) async -> PreviewDecision {
        await presentVariants(
            original: original,
            variants: [translated],
            persona: persona,
            isSourceFocused: isSourceFocused
        )
    }

    func presentVariants(
        original: String,
        variants: [String],
        persona: Persona,
        isSourceFocused: @escaping @MainActor () -> Bool
    ) async -> PreviewDecision {
        await withCheckedContinuation { continuation in
            show(
                original: original,
                variants: variants.isEmpty ? [""] : variants,
                persona: persona,
                isSourceFocused: isSourceFocused,
                continuation: continuation
            )
        }
    }

    private func show(
        original: String,
        variants: [String],
        persona: Persona,
        isSourceFocused: @escaping @MainActor () -> Bool,
        continuation: CheckedContinuation<PreviewDecision, Never>
    ) {
        let model = PreviewHUDViewModel(
            original: original,
            variants: variants,
            persona: persona
        )

        var resolved = false
        let resolve: @MainActor (PreviewDecision) -> Void = { [weak self] decision in
            guard let self, !resolved else { return }
            resolved = true
            self.dismiss()
            continuation.resume(returning: decision)
        }

        model.onSend = { resolve(.send(model.editableTranslation)) }
        model.onCancel = { resolve(.cancel) }

        let panel = panel ?? makePanel()
        panel.onTabPressed = { model.enterEditMode() }
        panel.onLeftArrowPressed = { model.selectPrevious() }
        panel.onRightArrowPressed = { model.selectNext() }
        panel.onCommandDigitPressed = { n in model.selectIndex(n - 1) }
        let hostingController = NSHostingController(rootView: PreviewHUDView(model: model))
        // `.minSize` lets the panel resize freely instead of snapping
        // back to the SwiftUI content's preferred size.
        hostingController.sizingOptions = .minSize
        panel.contentViewController = hostingController
        self.panel = panel
        self.hostingController = hostingController

        position(panel: panel)
        panel.makeKeyAndOrderFront(nil)
        startFocusMonitor(isSourceFocused: isSourceFocused, resolve: resolve)
    }

    private func dismiss() {
        focusMonitorTask?.cancel()
        focusMonitorTask = nil
        panel?.orderOut(nil)
    }

    private func startFocusMonitor(
        isSourceFocused: @escaping @MainActor () -> Bool,
        resolve: @escaping @MainActor (PreviewDecision) -> Void
    ) {
        focusMonitorTask?.cancel()
        focusMonitorTask = Task { @MainActor [focusLossTimeout, focusPollInterval] in
            var lostFocusSince: ContinuousClock.Instant?

            while !Task.isCancelled {
                if isSourceFocused() {
                    lostFocusSince = nil
                } else {
                    let now = ContinuousClock.now
                    if lostFocusSince == nil {
                        lostFocusSince = now
                    }
                    if let since = lostFocusSince,
                       since.duration(to: now) >= focusLossTimeout {
                        resolve(.cancel)
                        return
                    }
                }

                try? await Task.sleep(for: focusPollInterval)
            }
        }
    }

    private func makePanel() -> KeyableNonactivatingPanel {
        let panel = KeyableNonactivatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 220),
            // `.resizable` works on borderless panels — the user can
            // drag any edge to resize even without a visible frame.
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = false
        // Drag from any non-control area to reposition the preview.
        panel.isMovableByWindowBackground = true
        panel.minSize = NSSize(width: 380, height: 220)
        panel.maxSize = NSSize(width: 860, height: 720)
        return panel
    }

    private func position(panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let visibleFrame = NSScreen.screens
            .first(where: { $0.frame.contains(mouse) })?
            .visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero

        let size = NSSize(width: 500, height: 310)
        var origin = NSPoint(x: mouse.x + 14, y: mouse.y - size.height - 14)
        if origin.x + size.width > visibleFrame.maxX {
            origin.x = visibleFrame.maxX - size.width - 8
        }
        if origin.y < visibleFrame.minY {
            origin.y = mouse.y + 18
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }
}

// MARK: - View model + view

@MainActor
@Observable
final class PreviewHUDViewModel {
    let original: String
    let persona: Persona
    /// v0.8.5 — every variant the LLM produced (always ≥1; single-rewrite
    /// flow stores a one-element list). Edits to the active variant are
    /// captured in `variants[selectedIndex]` so paging back-and-forth
    /// preserves the user's tweaks.
    var variants: [String]
    /// Index of the active variant. Clamped to `variants.indices`.
    var selectedIndex: Int = 0
    var isEditing = false

    var onSend: () -> Void = {}
    var onCancel: () -> Void = {}

    convenience init(original: String, translated: String, persona: Persona) {
        self.init(original: original, variants: [translated], persona: persona)
    }

    init(original: String, variants: [String], persona: Persona) {
        self.original = original
        self.persona = persona
        self.variants = variants.isEmpty ? [""] : variants
    }

    /// Whether to show the variant pager UI (chip + ← → + ⌘N hints).
    var isMultiVariant: Bool { variants.count > 1 }

    /// The text the user is currently looking at. Two-way bound to the
    /// editor so edits land in `variants[selectedIndex]` automatically.
    var editableTranslation: String {
        get { variants.indices.contains(selectedIndex) ? variants[selectedIndex] : "" }
        set {
            guard variants.indices.contains(selectedIndex) else { return }
            variants[selectedIndex] = newValue
        }
    }

    func enterEditMode() {
        isEditing = true
    }

    func selectIndex(_ i: Int) {
        guard variants.indices.contains(i) else { return }
        selectedIndex = i
        // Leaving edit mode when paging avoids a stuck text-editor focus
        // on the previous variant.
        isEditing = false
    }

    func selectNext() {
        guard isMultiVariant else { return }
        selectIndex((selectedIndex + 1) % variants.count)
    }

    func selectPrevious() {
        guard isMultiVariant else { return }
        selectIndex((selectedIndex - 1 + variants.count) % variants.count)
    }
}

struct PreviewHUDView: View {
    @Bindable var model: PreviewHUDViewModel
    @FocusState private var editorFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(model.persona.displayBadge)
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.tint.opacity(0.18), in: Capsule())
                Text(model.persona.displayName)
                    .font(.headline)
                Spacer()
                // v0.8.5 — variant pager. Only rendered when the LLM
                // produced more than one draft.
                if model.isMultiVariant {
                    HStack(spacing: 6) {
                        Button {
                            model.selectPrevious()
                        } label: {
                            Image(systemName: "chevron.left")
                                .symbolRenderingMode(.hierarchical)
                        }
                        .buttonStyle(.borderless)
                        .help("Previous draft (←)")
                        .accessibilityLabel("Previous draft")

                        Text("\(model.selectedIndex + 1) / \(model.variants.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.secondary.opacity(0.12), in: Capsule())
                            .accessibilityLabel("Draft \(model.selectedIndex + 1) of \(model.variants.count)")

                        Button {
                            model.selectNext()
                        } label: {
                            Image(systemName: "chevron.right")
                                .symbolRenderingMode(.hierarchical)
                        }
                        .buttonStyle(.borderless)
                        .help("Next draft (→)")
                        .accessibilityLabel("Next draft")
                    }
                }
                Button {
                    model.enterEditMode()
                } label: {
                    Image(systemName: "pencil")
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.borderless)
                .controlSize(.large)
                .help("Edit translation")
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Original")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(model.original)
                    .font(.body)
                    .textSelection(.enabled)
                    .lineLimit(3)
                    .truncationMode(.tail)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(model.isMultiVariant ? "Draft \(model.selectedIndex + 1)" : "Translation")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if model.isEditing {
                    TextEditor(text: $model.editableTranslation)
                        .font(.body)
                        .frame(minHeight: 86, maxHeight: 110)
                        .focused($editorFocused)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(.separator, lineWidth: 1)
                        )
                } else {
                    ScrollView {
                        Text(model.editableTranslation)
                            .font(.body)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 86, maxHeight: 110)
                }
            }
            // v0.8.5 — keyboard hint footer when multiple drafts exist.
            if model.isMultiVariant {
                Text("← → switch • ⌘1–\(model.variants.count) jump • Tab edit • Return send • Esc cancel")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }

            HStack {
                Spacer()
                Button("Cancel") { model.onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button("Send") { model.onSend() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(minWidth: 380, idealWidth: 500, maxWidth: .infinity, alignment: .leading)
        .liquidGlassBackground(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.separator.opacity(0.6), lineWidth: 0.5)
        )
        .onChange(of: model.isEditing) { _, isEditing in
            if isEditing {
                Task { @MainActor in
                    editorFocused = true
                }
            }
        }
    }
}

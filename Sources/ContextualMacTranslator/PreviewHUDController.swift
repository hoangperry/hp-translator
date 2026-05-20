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
}

/// `NSPanel` subclass that can become key — required so SwiftUI's
/// `keyboardShortcut(.defaultAction / .cancelAction)` modifiers fire on
/// `Return` / `Esc`. Combined with `.nonactivatingPanel`, the panel becomes
/// key without bringing the entire app forward, preserving focus on the
/// original target app for the subsequent paste.
final class KeyableNonactivatingPanel: NSPanel {
    var onTabPressed: (() -> Void)?

    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 48 {
            onTabPressed?()
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
        await withCheckedContinuation { continuation in
            show(
                original: original,
                translated: translated,
                persona: persona,
                isSourceFocused: isSourceFocused,
                continuation: continuation
            )
        }
    }

    private func show(
        original: String,
        translated: String,
        persona: Persona,
        isSourceFocused: @escaping @MainActor () -> Bool,
        continuation: CheckedContinuation<PreviewDecision, Never>
    ) {
        let model = PreviewHUDViewModel(
            original: original,
            translated: translated,
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
        let hostingController = NSHostingController(rootView: PreviewHUDView(model: model))
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
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = false
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
    var editableTranslation: String
    var isEditing = false

    var onSend: () -> Void = {}
    var onCancel: () -> Void = {}

    init(original: String, translated: String, persona: Persona) {
        self.original = original
        self.persona = persona
        self.editableTranslation = translated
    }

    func enterEditMode() {
        isEditing = true
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
                Text("Translation")
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
        .frame(width: 500, alignment: .leading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.separator, lineWidth: 1)
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

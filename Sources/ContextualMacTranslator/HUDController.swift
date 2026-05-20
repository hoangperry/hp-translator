import AppKit
import SwiftUI

enum HUDKind {
    case loading
    case result
    case error
}

struct HUDState {
    let kind: HUDKind
    let title: String
    let message: String
    let personaName: String?
}

@MainActor
final class HUDController {
    private var panel: NSPanel?
    private var hostingController: NSHostingController<HUDView>?
    private var hideTask: Task<Void, Never>?
    private var clickMonitor: Any?

    func showLoading(_ message: String, persona: Persona) {
        show(HUDState(
            kind: .loading,
            title: persona.displayName,
            message: message,
            personaName: nil
        ), autoHideAfter: nil)
    }

    /// Update the HUD with a partial translation as chunks stream in.
    /// Keeps the spinner so the user knows more is still coming. Cancels
    /// any pending auto-hide so a slow stream doesn't get cut off.
    func updateLoading(_ partial: String, persona: Persona) {
        show(HUDState(
            kind: .loading,
            title: persona.displayName,
            message: partial,
            personaName: nil
        ), autoHideAfter: nil)
    }

    func showResult(_ message: String, persona: Persona) {
        show(HUDState(
            kind: .result,
            title: "Translation",
            message: message,
            personaName: persona.displayName
        ), autoHideAfter: .seconds(8))
    }

    func showError(_ message: String) {
        show(HUDState(
            kind: .error,
            title: "Translator Error",
            message: message,
            personaName: nil
        ), autoHideAfter: .seconds(6))
    }

    /// Hide the HUD immediately. Called by the workflow before opening
    /// the preview HUD so the user doesn't see two stacked panels (the
    /// trailing "Translating message..." loading HUD plus the preview).
    func dismiss() {
        hideTask?.cancel()
        hideTask = nil
        uninstallDismissMonitors()
        panel?.orderOut(nil)
    }

    private func show(_ state: HUDState, autoHideAfter delay: Duration?) {
        hideTask?.cancel()
        let panel = panel ?? makePanel()
        let hostingController = hostingController ?? makeHostingController(state: state)
        hostingController.rootView = HUDView(
            state: state,
            onDismiss: { [weak self] in self?.dismiss() }
        )
        panel.contentViewController = hostingController
        self.panel = panel
        self.hostingController = hostingController

        position(panel: panel, hostingView: hostingController.view)
        panel.orderFrontRegardless()
        installDismissMonitors()

        if let delay {
            hideTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: delay)
                self?.dismiss()
            }
        }
    }

    /// Click-anywhere-outside-the-panel to dismiss. Uses a global event
    /// monitor (fires only when *another* app receives the click, since
    /// `.nonactivatingPanel` keeps focus elsewhere). We don't add a local
    /// monitor because clicks inside the panel hit SwiftUI controls (the
    /// X button) directly — no need to also dismiss on those.
    ///
    /// Esc would be nice but a global key monitor would intercept Esc
    /// in every other app while the HUD is up, which is intrusive. The
    /// X button + click-outside + auto-hide timer cover dismissal.
    private func installDismissMonitors() {
        uninstallDismissMonitors()
        clickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in
                self?.dismiss()
            }
        }
    }

    private func uninstallDismissMonitors() {
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 120),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.level = .floating
        // Removed `.transient` — it caused the panel to disappear within
        // ~0.5s when the originating app reasserted focus, so users couldn't
        // read the HUD content. Dismissal now relies on:
        //   1. Auto-hide timer (6s error / 8s result)
        //   2. X close button on the panel
        //   3. Click anywhere outside the panel (global event monitor)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        return panel
    }

    private func makeHostingController(state: HUDState) -> NSHostingController<HUDView> {
        NSHostingController(rootView: HUDView(state: state, onDismiss: {}))
    }

    private func position(panel: NSPanel, hostingView: NSView) {
        hostingView.layoutSubtreeIfNeeded()
        let fittingSize = hostingView.fittingSize
        let width: CGFloat = 380
        let height = min(max(fittingSize.height, 92), 280)
        let mouse = NSEvent.mouseLocation
        let visibleFrame = NSScreen.screens
            .first(where: { $0.frame.contains(mouse) })?
            .visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero

        var origin = NSPoint(x: mouse.x + 14, y: mouse.y - height - 14)
        if origin.x + width > visibleFrame.maxX {
            origin.x = visibleFrame.maxX - width - 8
        }
        if origin.y < visibleFrame.minY {
            origin.y = mouse.y + 18
        }

        panel.setFrame(NSRect(origin: origin, size: NSSize(width: width, height: height)), display: true)
    }
}

/// macOS 26 Tahoe introduced Liquid Glass via `.glassEffect(in:)`. On older
/// systems we fall back to `.regularMaterial` + `clipShape`, which is the
/// closest visual approximation and what the app shipped with before.
extension View {
    @ViewBuilder
    func panelBackground<S: Shape>(in shape: S) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(in: shape)
        } else {
            self.background(.regularMaterial)
                .clipShape(shape)
        }
    }
}

struct HUDView: View {
    let state: HUDState
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                statusIcon
                Text(state.title)
                    .font(.headline)
                Spacer(minLength: 8)
                if let personaName = state.personaName {
                    Text(personaName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                        .font(.system(size: 16, weight: .regular))
                }
                .buttonStyle(.plain)
                .help("Dismiss")
                .accessibilityLabel("Dismiss")
            }

            Text(state.message)
                .font(.body)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(width: 380, alignment: .leading)
        .panelBackground(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.separator.opacity(0.6), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch state.kind {
        case .loading:
            ProgressView()
                .controlSize(.small)
        case .result:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .symbolRenderingMode(.hierarchical)
                .symbolEffect(.bounce, value: state.message)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .symbolRenderingMode(.hierarchical)
                .symbolEffect(.pulse, value: state.message)
        }
    }
}

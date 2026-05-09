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

    private func show(_ state: HUDState, autoHideAfter delay: Duration?) {
        hideTask?.cancel()
        let panel = panel ?? makePanel()
        let hostingController = hostingController ?? makeHostingController(state: state)
        hostingController.rootView = HUDView(state: state)
        panel.contentViewController = hostingController
        self.panel = panel
        self.hostingController = hostingController

        position(panel: panel, hostingView: hostingController.view)
        panel.orderFrontRegardless()

        if let delay {
            hideTask = Task { @MainActor in
                try? await Task.sleep(for: delay)
                panel.orderOut(nil)
            }
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
        // read the HUD content. We now rely on the explicit `hideTask`
        // delay (6s for errors, 8s for results) for dismissal.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        return panel
    }

    private func makeHostingController(state: HUDState) -> NSHostingController<HUDView> {
        NSHostingController(rootView: HUDView(state: state))
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

struct HUDView: View {
    let state: HUDState

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
            }

            Text(state.message)
                .font(.body)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(width: 380, alignment: .leading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.white.opacity(0.18), lineWidth: 1)
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
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }
}

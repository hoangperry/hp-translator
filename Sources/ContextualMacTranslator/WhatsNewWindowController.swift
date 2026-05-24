import AppKit
import SwiftUI

/// One-shot window shown on first launch of a new minor/major version
/// to surface what's new in this build. Driven by
/// `SettingsStore.lastShownWhatsNewVersion` vs the running
/// `CFBundleShortVersionString` — if they don't match, the window
/// appears once, then the user's seen-version is bumped.
///
/// Why a window, not a Settings sheet: the app is LSUIElement (no Dock
/// icon, no main window). The user might never open Settings, so a
/// passive "next time you open Settings you'll see it" surface won't
/// reach them. A dedicated window pops the AppKit equivalent of "Hi,
/// here's what changed" without forcing the user into Settings first.
@MainActor
final class WhatsNewWindowController {
    private let window: NSWindow

    init(version: String, highlights: [Highlight], onContinue: @escaping @MainActor () -> Void) {
        let view = WhatsNewView(version: version, highlights: highlights, onContinue: onContinue)
        let controller = NSHostingController(rootView: view)
        window = NSWindow(contentViewController: controller)
        window.title = "What's New in v\(version)"
        window.setContentSize(NSSize(width: 560, height: 440))
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.center()
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func close() {
        window.close()
    }

    /// One bullet on the What's-New screen. SF Symbol + headline +
    /// supporting description. Keep descriptions tight — this isn't
    /// the release notes, just a teaser pointing the user at the
    /// surface (Settings page, Shortcuts.app, hotkey).
    struct Highlight: Identifiable {
        let id = UUID()
        let symbol: String
        let title: String
        let body: String
    }
}

private struct WhatsNewView: View {
    let version: String
    let highlights: [WhatsNewWindowController.Highlight]
    let onContinue: @MainActor () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("What's New")
                    .font(.title2.bold())
                Text("Contextual Mac Translator v\(version)")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 14) {
                ForEach(highlights) { h in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: h.symbol)
                            .font(.title3)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.tint)
                            .frame(width: 28, alignment: .center)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(h.title)
                                .font(.headline)
                            Text(h.body)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("Got it") { onContinue() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(minWidth: 520, minHeight: 400)
        .liquidGlassBackground(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// Static catalogue of the highlights shown in v0.9.0. Lives here
/// (next to the controller) instead of in AppDelegate so the copy is
/// easy to find when bumping for v0.9.x / v1.0.
extension WhatsNewWindowController {
    static let v0_9_0Highlights: [Highlight] = [
        .init(
            symbol: "command",
            title: "Shortcuts.app & Siri support",
            body: "Three new App Intents — Translate Text, Rewrite with Tone, Rewrite with Instruction — let you call the translator from Shortcuts, Spotlight, Raycast, or Siri. Drop them into any workflow."
        ),
        .init(
            symbol: "camera.viewfinder",
            title: "OCR-from-screen translate",
            body: "Bind a hotkey, drag a region anywhere on screen, and the app reads the text (Vietnamese / English / Chinese / Japanese / Korean) and translates it for you. No more retyping from Aliwangwang or a paused video."
        ),
        .init(
            symbol: "gear",
            title: "Find both in Settings → Capture",
            body: "Set the OCR hotkey in the new Capture section. The App Intents appear automatically in Shortcuts.app once the app has launched at least once."
        ),
    ]
}

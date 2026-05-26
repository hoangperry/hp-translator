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
        // v0.10.5 — reverted transparent-titlebar / clear-background.
        // Title text was rendering directly onto the desktop with no
        // contrast on real macOS. Standard opaque titlebar restored.
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
    }

    func show() {
        // Surface the window without stealing focus from whichever app
        // the user is currently typing in. Sparkle can pop this mid-day
        // after a silent OTA upgrade; yanking focus during a typed
        // sentence would be hostile. The user can click into it when
        // they're ready (the window joins all spaces + is .floating
        // free, so it stays visible until dismissed).
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.level = .floating
        window.orderFrontRegardless()
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

/// Catalogue of highlights per version. Add new entries as minor/major
/// releases ship — the absence of an entry for a version (rather than
/// a hard-coded version prefix) is what gates the What's-New popup.
/// This way v0.10.0 / v1.0.0 silently no-op until someone wires their
/// own highlight set instead of mis-replaying the v0.9.0 copy.
extension WhatsNewWindowController {
    /// Highlights for a specific app version (CFBundleShortVersionString
    /// equality, not prefix). Returns `nil` when no highlights exist for
    /// the running build — AppDelegate uses this to decide whether to
    /// show the window at all.
    static func highlights(for version: String) -> [Highlight]? {
        switch version {
        case "0.9.0":
            return v0_9_0Highlights
        case "0.10.0":
            return v0_10_0Highlights
        default:
            return nil
        }
    }

    /// v0.10.0 — "Cultural Precision & Privacy" anchor narrative
    /// (Q4 from define.md §8: "v0.10.0 hiểu xưng hô — anh/chị/em,
    /// Bắc/Nam, formal/chat; và không gửi dữ liệu khách ra nước
    /// ngoài khi dùng local mode.").
    static let v0_10_0Highlights: [Highlight] = [
        .init(
            symbol: "person.2.wave.2",
            title: "VN register card",
            body: "Pin your dialect (Bắc/Nam), kinship (anh/chị/em/cháu/bạn), and formality — every rewrite + outbound translate now matches. Apple Intelligence can't do this per-locale precision. Settings → Contextual rewrite."
        ),
        .init(
            symbol: "shield.lefthalf.filled",
            title: "Privacy badge + Ollama onboarding",
            body: "Every PreviewHUD shows whether your text went Local / Cloud / Hosted. Settings → Privacy has a one-click Ollama install helper + test-connection — không gửi dữ liệu khách ra nước ngoài khi dùng local mode."
        ),
        .init(
            symbol: "list.bullet.rectangle",
            title: "Glossary v2",
            body: "Three new structured rule kinds: Don't translate (brands / code), Alias (casing), Always translate (jargon). Replaces the free-text blob with typed entries the LLM follows exactly. Your legacy free-text rules still flow underneath."
        ),
    ]

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

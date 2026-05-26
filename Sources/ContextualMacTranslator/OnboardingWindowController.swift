import AppKit
import SwiftUI

/// v0.10.2 — distinguishes the truly-first-launch flow (user has never
/// seen the permission helper) from the recovery flow (Accessibility
/// was previously granted but macOS reset it during a Sparkle upgrade
/// or some other TCC event). The two cases need different copy: the
/// recovery card has to acknowledge that the user already did this
/// once and explain why they're seeing it again.
enum OnboardingMode: Sendable {
    case firstRun
    case permissionRecovery
}

@MainActor
final class OnboardingWindowController {
    private let window: NSWindow

    init(
        permissionManager: PermissionManager,
        mode: OnboardingMode = .firstRun,
        onContinue: @escaping @MainActor () -> Void
    ) {
        let view = OnboardingView(
            permissionManager: permissionManager,
            mode: mode,
            onContinue: onContinue
        )
        let controller = NSHostingController(rootView: view)
        window = NSWindow(contentViewController: controller)
        window.title = "Contextual Mac Translator"
        window.setContentSize(NSSize(width: 620, height: 500))
        // v0.10.5 — reverted the transparent-titlebar / clear-background
        // experiment from v0.7.x. On real macOS the combination of
        // `titlebarAppearsTransparent = true` + `backgroundColor = .clear`
        // + `.fullSizeContentView` makes the window title text render
        // straight onto the desktop wallpaper with zero contrast, which
        // looks broken. Use a standard opaque titlebar; the SwiftUI
        // content's `liquidGlassBackground` modifier still applies its
        // material to the content area on macOS 26.
        window.styleMask = [.titled, .closable]
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
}

private struct OnboardingView: View {
    var permissionManager: PermissionManager
    let mode: OnboardingMode
    let onContinue: @MainActor () -> Void

    private var isInApplicationsFolder: Bool {
        Bundle.main.bundleURL.path.hasPrefix("/Applications/")
    }

    private var headline: String {
        switch mode {
        case .firstRun: return "First Launch Setup"
        case .permissionRecovery: return "Permissions Need Re-Granting"
        }
    }

    private var subhead: String {
        switch mode {
        case .firstRun:
            return "Grant Accessibility so the app can copy selected text, paste translations, and press Return in the target app."
        case .permissionRecovery:
            return "Welcome back. macOS cleared the app's Accessibility grant after the recent update — translate hotkeys are silent until you re-grant. Click Request below, or Open Settings if the prompt does not appear."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(headline)
                    .font(.title2.bold())
                Text(subhead)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !permissionManager.accessibilityGranted {
                Label("If Accessibility is already enabled in System Settings but this screen is not green yet, continue anyway and restart the app once. macOS can lag for unsigned local builds.", systemImage: "info.circle")
                    .symbolRenderingMode(.hierarchical)
                    .font(.callout)
                    .foregroundStyle(.blue)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !isInApplicationsFolder {
                Label("Move the app to /Applications before daily use so macOS keeps permission grants stable.", systemImage: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 12) {
                // v0.10.4 — Input Monitoring row removed. The app uses
                // Carbon `RegisterEventHotKey` for global hotkeys and
                // `CGEvent` to post Cmd+C/V — neither needs Input
                // Monitoring. Asking for a permission we never actually
                // use was pure friction (and the macOS API silently
                // suppresses the prompt after the first denial, so the
                // Request button could never recover the state anyway).
                OnboardingPermissionRow(
                    title: "Accessibility",
                    badge: "Required",
                    description: "Required for Command-C, Command-V, and Return automation.",
                    granted: permissionManager.accessibilityGranted,
                    openSettings: openAccessibilitySettings,
                    request: permissionManager.requestAccessibilityIfNeeded,
                    showApp: showAppInFinder
                )
            }

            VStack(alignment: .leading, spacing: 6) {
                Label("If the app is not listed, open the privacy pane, press +, then choose /Applications/Contextual Mac Translator.app.", systemImage: "plus.app")
                    .symbolRenderingMode(.hierarchical)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Label("After granting Accessibility, quit and reopen the app if hotkeys do not respond immediately.", systemImage: "arrow.clockwise")
                    .symbolRenderingMode(.hierarchical)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            HStack {
                Button("Refresh") {
                    permissionManager.refresh()
                }
                .controlSize(.large)
                Spacer()
                Button(permissionManager.accessibilityGranted ? "Continue" : "Continue Anyway") {
                    onContinue()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 40)
        .padding(.bottom, 24)
        .frame(width: 620, height: 500)
        // Real Liquid Glass backing (`.glassEffect()` on macOS 26) — pairs
        // with the non-opaque window so the desktop refracts through.
        .liquidGlassBackground(in: Rectangle())
        .task {
            while !Task.isCancelled {
                permissionManager.refresh()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func openAccessibilitySettings() {
        openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    private func openSettings(_ value: String) {
        guard let url = URL(string: value) else { return }
        NSWorkspace.shared.open(url)
    }

    private func showAppInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }
}

private struct OnboardingPermissionRow: View {
    let title: String
    let badge: String
    let description: String
    let granted: Bool
    let openSettings: () -> Void
    let request: () -> Void
    let showApp: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(granted ? .green : .secondary)
                    .symbolRenderingMode(.hierarchical)
                    .symbolEffect(.bounce, value: granted)
                Text(title)
                    .font(.headline)
                Text(badge)
                    .font(.caption.bold())
                    .foregroundStyle(badge == "Required" ? .orange : .secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(.secondary.opacity(0.12), in: Capsule())
                Spacer()
                Button("Open Settings", action: openSettings)
                Button(granted ? "Granted" : "Request", action: request)
                    .disabled(granted)
            }
            Text(description)
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.leading, 30)
            HStack(spacing: 8) {
                Button("Show App") {
                    showApp()
                }
                Text("Use this if macOS does not list the app automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, 30)
        }
        .padding(14)
        // A plain content card — NOT glass. The window itself already
        // carries the Liquid Glass layer; stacking glass-on-glass renders
        // wrong because glass cannot sample other glass.
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.separator.opacity(0.4), lineWidth: 0.5)
        )
    }
}

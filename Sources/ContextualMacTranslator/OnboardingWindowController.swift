import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController {
    private let window: NSWindow

    init(permissionManager: PermissionManager, onContinue: @escaping @MainActor () -> Void) {
        let view = OnboardingView(permissionManager: permissionManager, onContinue: onContinue)
        let controller = NSHostingController(rootView: view)
        window = NSWindow(contentViewController: controller)
        window.title = "Contextual Mac Translator"
        window.setContentSize(NSSize(width: 620, height: 500))
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
    @ObservedObject var permissionManager: PermissionManager
    let onContinue: @MainActor () -> Void

    private var isInApplicationsFolder: Bool {
        Bundle.main.bundleURL.path.hasPrefix("/Applications/")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("First Launch Setup")
                    .font(.title2.bold())
                Text("Grant Accessibility so the app can copy selected text, paste translations, and press Return in the target app.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !permissionManager.accessibilityGranted {
                Label("If Accessibility is already enabled in System Settings but this screen is not green yet, continue anyway and restart the app once. macOS can lag for unsigned local builds.", systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.blue)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !isInApplicationsFolder {
                Label("Move the app to /Applications before daily use so macOS keeps permission grants stable.", systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 12) {
                OnboardingPermissionRow(
                    title: "Accessibility",
                    badge: "Required",
                    description: "Required for Command-C, Command-V, and Return automation.",
                    granted: permissionManager.accessibilityGranted,
                    openSettings: openAccessibilitySettings,
                    request: permissionManager.requestAccessibilityIfNeeded,
                    showApp: showAppInFinder
                )
                OnboardingPermissionRow(
                    title: "Input Monitoring",
                    badge: "Optional",
                    description: "Only needed if macOS later asks for keyboard monitoring. You can continue without it.",
                    granted: permissionManager.inputMonitoringGranted,
                    openSettings: openInputMonitoringSettings,
                    request: permissionManager.requestInputMonitoringIfNeeded,
                    showApp: showAppInFinder
                )
            }

            VStack(alignment: .leading, spacing: 6) {
                Label("If the app is not listed, open the privacy pane, press +, then choose /Applications/Contextual Mac Translator.app.", systemImage: "plus.app")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Label("After granting Accessibility, quit and reopen the app if hotkeys do not respond immediately.", systemImage: "arrow.clockwise")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            HStack {
                Button("Refresh") {
                    permissionManager.refresh()
                }
                Spacer()
                Button(permissionManager.accessibilityGranted ? "Continue" : "Continue Anyway") {
                    onContinue()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 620, height: 500)
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

    private func openInputMonitoringSettings() {
        openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
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
    }
}

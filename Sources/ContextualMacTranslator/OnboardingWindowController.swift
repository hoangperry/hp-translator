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
        window.setContentSize(NSSize(width: 540, height: 370))
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

    private var canContinue: Bool {
        permissionManager.accessibilityGranted && permissionManager.inputMonitoringGranted
    }

    private var isInApplicationsFolder: Bool {
        Bundle.main.bundleURL.path.hasPrefix("/Applications/")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("First Launch Setup")
                    .font(.title2.bold())
                Text("Grant the macOS permissions required for global hotkeys and keyboard automation.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !isInApplicationsFolder {
                Label("Move the app to /Applications before daily use so macOS keeps permission grants stable.", systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 10) {
                OnboardingPermissionRow(
                    title: "Accessibility",
                    granted: permissionManager.accessibilityGranted,
                    openSettings: openAccessibilitySettings,
                    request: permissionManager.requestAccessibilityIfNeeded
                )
                OnboardingPermissionRow(
                    title: "Input Monitoring",
                    granted: permissionManager.inputMonitoringGranted,
                    openSettings: openInputMonitoringSettings,
                    request: permissionManager.requestInputMonitoringIfNeeded
                )
            }

            Spacer()

            HStack {
                Button("Refresh") {
                    permissionManager.refresh()
                }
                Spacer()
                Button("Continue") {
                    onContinue()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canContinue)
            }
        }
        .padding(22)
        .frame(width: 540, height: 370)
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
}

private struct OnboardingPermissionRow: View {
    let title: String
    let granted: Bool
    let openSettings: () -> Void
    let request: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(granted ? .green : .secondary)
            Text(title)
                .font(.headline)
            Spacer()
            Button("Open Settings", action: openSettings)
            Button(granted ? "Granted" : "Request", action: request)
                .disabled(granted)
        }
    }
}

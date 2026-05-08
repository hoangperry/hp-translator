import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private let window: NSWindow

    init(permissionManager: PermissionManager) {
        let view = SettingsView(permissionManager: permissionManager)
        let controller = NSHostingController(rootView: view)
        window = NSWindow(contentViewController: controller)
        window.title = "Contextual Mac Translator"
        window.setContentSize(NSSize(width: 560, height: 570))
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

struct SettingsView: View {
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject var permissionManager: PermissionManager

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Backend")
                    .font(.headline)
                TextField("https://your-api.example.com/translate", text: $settings.endpoint)
                    .textFieldStyle(.roundedBorder)
                if let endpointWarning = EndpointPolicy.warning(for: settings.endpoint) {
                    Label(endpointWarning, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                SecureField("Bearer token", text: $settings.apiKey)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Glossary")
                    .font(.headline)
                TextEditor(text: $settings.glossary)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 140)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(.separator, lineWidth: 1)
                    )
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Permissions")
                    .font(.headline)
                PermissionRow(
                    title: "Accessibility",
                    granted: permissionManager.accessibilityGranted,
                    action: permissionManager.requestAccessibilityIfNeeded
                )
                PermissionRow(
                    title: "Input Monitoring",
                    granted: permissionManager.inputMonitoringGranted,
                    action: permissionManager.requestInputMonitoringIfNeeded
                )
                HStack {
                    Button("Refresh") {
                        permissionManager.refresh()
                    }
                    Button("Open Privacy Settings") {
                        openPrivacySettings()
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Advanced")
                    .font(.headline)
                Toggle("Enable focus guard before paste/send", isOn: $settings.focusGuardEnabled)
            }

            Spacer()
        }
        .padding(22)
        .frame(width: 560, height: 570)
    }

    private func openPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}

private struct PermissionRow: View {
    let title: String
    let granted: Bool
    let action: () -> Void

    var body: some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(granted ? .green : .red)
            Text(title)
            Spacer()
            Button(granted ? "Granted" : "Request", action: action)
                .disabled(granted)
        }
    }
}

import AppKit
import ApplicationServices

@MainActor
final class PermissionManager: ObservableObject {
    @Published private(set) var accessibilityGranted: Bool = AXIsProcessTrusted()
    @Published private(set) var inputMonitoringGranted: Bool = CGPreflightListenEventAccess()

    func refresh() {
        accessibilityGranted = AXIsProcessTrusted()
        inputMonitoringGranted = CGPreflightListenEventAccess()
    }

    func requestAccessibilityIfNeeded() {
        refresh()
        guard !accessibilityGranted else { return }

        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        refreshLater()
    }

    func requestInputMonitoringIfNeeded() {
        refresh()
        guard !inputMonitoringGranted else { return }

        _ = CGRequestListenEventAccess()
        refreshLater()
    }

    private func refreshLater() {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            refresh()
        }
    }
}

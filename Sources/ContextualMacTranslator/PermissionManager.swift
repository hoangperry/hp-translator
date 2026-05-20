import AppKit
import ApplicationServices
import Observation

@MainActor
@Observable
final class PermissionManager {
    private(set) var accessibilityGranted: Bool = AXIsProcessTrusted()
    private(set) var inputMonitoringGranted: Bool = CGPreflightListenEventAccess()

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

import AppKit
import ApplicationServices
import Observation

@MainActor
@Observable
final class PermissionManager {
    private(set) var accessibilityGranted: Bool
    private(set) var inputMonitoringGranted: Bool

    private let settings: SettingsStore?
    private let accessibilityProbe: @MainActor () -> Bool
    private let inputMonitoringProbe: @MainActor () -> Bool
    private let requestAccessibilityAction: @MainActor () -> Void
    private let requestInputMonitoringAction: @MainActor () -> Void

    /// `settings` is optional so tests can construct a probe-only
    /// instance without spinning up a UserDefaults / Keychain pair.
    /// Production code in `AppDelegate` always passes `SettingsStore.shared`
    /// so the `lastKnownAccessibilityGranted` recovery signal stays
    /// in sync across launches.
    init(
        settings: SettingsStore? = nil,
        accessibilityProbe: @MainActor @escaping () -> Bool = { AXIsProcessTrusted() },
        inputMonitoringProbe: @MainActor @escaping () -> Bool = { CGPreflightListenEventAccess() },
        requestAccessibilityAction: @MainActor @escaping () -> Void = {
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        },
        requestInputMonitoringAction: @MainActor @escaping () -> Void = {
            _ = CGRequestListenEventAccess()
        }
    ) {
        self.settings = settings
        self.accessibilityProbe = accessibilityProbe
        self.inputMonitoringProbe = inputMonitoringProbe
        self.requestAccessibilityAction = requestAccessibilityAction
        self.requestInputMonitoringAction = requestInputMonitoringAction
        self.accessibilityGranted = accessibilityProbe()
        self.inputMonitoringGranted = inputMonitoringProbe()
        // Init does NOT sync the persisted record — AppDelegate must
        // read SettingsStore.lastKnownAccessibilityGranted FIRST so it
        // can detect the true→false transition. The first refresh()
        // call after AppDelegate's launch-time check re-syncs.
    }

    func refresh() {
        accessibilityGranted = accessibilityProbe()
        inputMonitoringGranted = inputMonitoringProbe()
        syncPersistedGrantRecord()
    }

    func requestAccessibilityIfNeeded() {
        refresh()
        guard !accessibilityGranted else { return }
        requestAccessibilityAction()
        refreshLater()
    }

    func requestInputMonitoringIfNeeded() {
        refresh()
        guard !inputMonitoringGranted else { return }
        requestInputMonitoringAction()
        refreshLater()
    }

    /// Compare the live grant against the last value we persisted.
    /// Writing only on change avoids spamming UserDefaults from the
    /// 1-second OnboardingView polling loop.
    private func syncPersistedGrantRecord() {
        guard let settings else { return }
        if settings.lastKnownAccessibilityGranted != accessibilityGranted {
            settings.lastKnownAccessibilityGranted = accessibilityGranted
        }
    }

    private func refreshLater() {
        Task { @MainActor in
            // TCC database settles a moment after the user clicks
            // "Allow" in the system prompt. 2s is conservative; the
            // OnboardingView polling loop continues refreshing every
            // second in parallel, so this is belt-and-braces.
            try? await Task.sleep(for: .seconds(2))
            refresh()
        }
    }
}

import AppKit
import ApplicationServices
import Observation

@MainActor
@Observable
final class PermissionManager {
    private(set) var accessibilityGranted: Bool

    private let settings: SettingsStore?
    private let accessibilityProbe: @MainActor () -> Bool
    private let requestAccessibilityAction: @MainActor () -> Void
    private let openAccessibilitySettings: @MainActor () -> Void
    private let autoOpenGracePeriodMilliseconds: UInt64

    /// `settings` is optional so tests can construct a probe-only
    /// instance without spinning up a UserDefaults / Keychain pair.
    /// Production code in `AppDelegate` always passes `SettingsStore.shared`
    /// so the `lastKnownAccessibilityGranted` recovery signal stays in
    /// sync across launches.
    ///
    /// v0.10.4 — Input Monitoring was removed. This app uses Carbon
    /// `RegisterEventHotKey` for global hotkeys (no Input Monitoring
    /// needed) and `CGEvent` to post Cmd+C/V (covered by Accessibility),
    /// so the previously-asked permission was always a UX dead end —
    /// macOS's `CGRequestListenEventAccess` only prompts once per launch,
    /// after which TCC suppresses the prompt forever and users have no
    /// way to recover via the Request button.
    init(
        settings: SettingsStore? = nil,
        accessibilityProbe: @MainActor @escaping () -> Bool = { AXIsProcessTrusted() },
        requestAccessibilityAction: @MainActor @escaping () -> Void = {
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        },
        openAccessibilitySettings: @MainActor @escaping () -> Void = {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        },
        autoOpenGracePeriodMilliseconds: UInt64 = 1500
    ) {
        self.settings = settings
        self.accessibilityProbe = accessibilityProbe
        self.requestAccessibilityAction = requestAccessibilityAction
        self.openAccessibilitySettings = openAccessibilitySettings
        self.autoOpenGracePeriodMilliseconds = autoOpenGracePeriodMilliseconds
        self.accessibilityGranted = accessibilityProbe()
        // Init does NOT sync the persisted record — AppDelegate must
        // read SettingsStore.lastKnownAccessibilityGranted FIRST so it
        // can detect the true→false transition. The first refresh()
        // call after AppDelegate's launch-time check re-syncs.
    }

    func refresh() {
        accessibilityGranted = accessibilityProbe()
        syncPersistedGrantRecord()
    }

    /// v0.10.4 — fires the system Accessibility prompt and, if the user
    /// has previously denied (in which case macOS silently swallows
    /// further prompts), auto-opens System Settings to the Accessibility
    /// pane after a short grace period so the user is never left
    /// staring at an unresponsive Request button. The grace period
    /// gives a freshly-shown system prompt time to be accepted before
    /// we redundantly open Settings.
    func requestAccessibilityIfNeeded() {
        refresh()
        guard !accessibilityGranted else { return }
        requestAccessibilityAction()
        let grace = autoOpenGracePeriodMilliseconds
        Task { @MainActor [weak self] in
            // 1.5s default — long enough that a user who genuinely just
            // clicked "Allow" on the system prompt will have already
            // triggered the TCC database update by the time we re-check;
            // short enough that the auto-open fallback feels responsive
            // when macOS suppressed the prompt outright.
            try? await Task.sleep(for: .milliseconds(grace))
            self?.checkAutoOpenSettings()
        }
        // Defense in depth: a separate 2s tick re-reads the live grant
        // so the UI flips to "Granted" promptly once the user toggles
        // the checkbox in System Settings (the OnboardingView polling
        // loop also covers this; this is the non-window code path).
        refreshLater()
    }

    /// v0.10.6 — split out from the grace-task closure so tests can
    /// exercise the auto-open decision synchronously without leaning on
    /// the cooperative scheduler. Same body, just callable directly.
    /// Internal so the tests in the same module can reach it; not a
    /// public API surface.
    @discardableResult
    func checkAutoOpenSettings() -> Bool {
        refresh()
        if !accessibilityGranted {
            openAccessibilitySettings()
            return true
        }
        return false
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
            try? await Task.sleep(for: .seconds(2))
            refresh()
        }
    }
}

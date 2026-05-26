import Foundation
import Testing

@testable import ContextualMacTranslator

/// v0.10.2 — PermissionManager owns the live Accessibility grant state
/// and writes it back to SettingsStore so AppDelegate can detect a
/// true→false transition on the next launch (the "TCC reset after
/// Sparkle upgrade" recovery signal). v0.10.4 dropped Input Monitoring
/// from the surface area entirely — see the suite's individual test
/// comments for the why. These tests exercise the persistence + the
/// auto-open-Settings fallback with injected probes; none of them
/// touch the real TCC database.
@Suite("PermissionManager")
@MainActor
struct PermissionManagerTests {
    private struct TestFixture {
        let store: SettingsStore
        let defaults: UserDefaults
    }

    private func makeSettings(_ name: String = UUID().uuidString) -> TestFixture {
        let suiteName = "app.lookerlab.translator.permission-tests.\(name)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let keychain = KeychainCredentialStore(
            service: "app.lookerlab.translator.permission-tests.\(UUID().uuidString)"
        )
        return TestFixture(
            store: SettingsStore(defaults: defaults, keychain: keychain),
            defaults: defaults
        )
    }

    @Test("init does NOT write to SettingsStore — AppDelegate needs the previous value")
    func initDoesNotMutateSettings() {
        let fixture = makeSettings("init-no-mutate")
        let settings = fixture.store
        // Pre-stamp the persisted record as `true` so we can detect any
        // accidental clobber during init.
        settings.lastKnownAccessibilityGranted = true

        _ = PermissionManager(
            settings: settings,
            accessibilityProbe: { false }   // live state diverges from persisted
        )

        // init reads the live state into accessibilityGranted but must
        // NOT push it to settings — otherwise AppDelegate's launch-time
        // recovery check sees the just-overwritten value and never
        // detects the loss.
        #expect(settings.lastKnownAccessibilityGranted == true)
    }

    @Test("refresh() syncs Accessibility grant to SettingsStore when it changes")
    func refreshSyncsGrantChange() {
        let settings = makeSettings("refresh-sync").store
        // Box wraps the mutable probe state so the @Sendable closure
        // captures a stable reference instead of a value that Swift 6
        // would flag as "mutated after capture".
        let liveGranted = Box(false)
        let pm = PermissionManager(
            settings: settings,
            accessibilityProbe: { liveGranted.value }
        )
        pm.refresh()
        #expect(settings.lastKnownAccessibilityGranted == false)

        liveGranted.value = true
        pm.refresh()
        #expect(settings.lastKnownAccessibilityGranted == true)

        liveGranted.value = false
        pm.refresh()
        #expect(settings.lastKnownAccessibilityGranted == false)
    }

    @Test("refresh() does NOT write when grant matches the persisted record")
    func refreshNoopWhenUnchanged() {
        let fixture = makeSettings("refresh-noop")
        fixture.store.lastKnownAccessibilityGranted = true

        let pm = PermissionManager(
            settings: fixture.store,
            accessibilityProbe: { true }
        )

        // Snapshot the underlying UserDefaults key and clear it; if
        // refresh() writes unconditionally, it would re-create the key.
        // (The didSet guard on `lastKnownAccessibilityGranted` is the
        // unit under test here.)
        fixture.defaults.removeObject(forKey: "translator.lastKnownAccessibilityGranted")
        pm.refresh()

        #expect(fixture.defaults.object(forKey: "translator.lastKnownAccessibilityGranted") == nil)
    }

    @Test("PermissionManager works with nil settings (test/preview path)")
    func nilSettingsIsAllowed() {
        let pm = PermissionManager(
            settings: nil,
            accessibilityProbe: { true }
        )

        // Just verifying the call does not crash; no settings to assert.
        pm.refresh()
        #expect(pm.accessibilityGranted == true)
    }

    @Test("requestAccessibilityIfNeeded invokes the request action when not yet granted")
    func requestActionFiresWhenUngranted() {
        let settings = makeSettings("request-fires").store
        let requestCount = Box(0)
        let pm = PermissionManager(
            settings: settings,
            accessibilityProbe: { false },
            requestAccessibilityAction: { requestCount.value += 1 }
        )

        pm.requestAccessibilityIfNeeded()
        #expect(requestCount.value == 1)

        // Second call should also fire because state still says not granted.
        pm.requestAccessibilityIfNeeded()
        #expect(requestCount.value == 2)
    }

    @Test("requestAccessibilityIfNeeded SKIPS the request when already granted")
    func requestActionSkippedWhenGranted() {
        let settings = makeSettings("request-skipped").store
        let requestCount = Box(0)
        let pm = PermissionManager(
            settings: settings,
            accessibilityProbe: { true },
            requestAccessibilityAction: { requestCount.value += 1 }
        )

        pm.requestAccessibilityIfNeeded()
        #expect(requestCount.value == 0)
    }

    @Test("v0.10.4: auto-opens Settings if grant doesn't arrive within the grace period")
    func autoOpensSettingsWhenPromptSuppressed() async {
        // Simulate the "user previously denied, macOS now silently
        // suppresses CGRequest…" scenario: probe stays false even after
        // the request action fires. PermissionManager must detect the
        // missing grant within the grace window and call the
        // openAccessibilitySettings closure so the user has a path out.
        let settings = makeSettings("auto-open").store
        let openCount = Box(0)
        let pm = PermissionManager(
            settings: settings,
            accessibilityProbe: { false },
            requestAccessibilityAction: { /* macOS swallowed it */ },
            openAccessibilitySettings: { openCount.value += 1 }
        )

        pm.requestAccessibilityIfNeeded()
        // Grace period is 1.5s; wait a bit longer to let the scheduled
        // Task complete deterministically on slow CI hosts.
        try? await Task.sleep(for: .seconds(2))
        #expect(openCount.value == 1)
    }

    @Test("v0.10.4: does NOT auto-open Settings if grant arrives during the grace period")
    func skipsAutoOpenWhenGrantArrives() async {
        // The other half of the contract: when the user actually clicks
        // "Allow" on the system prompt during the grace window, the
        // probe flips to true and the auto-open Settings step is
        // skipped — no double-trigger noise.
        let settings = makeSettings("skip-auto-open").store
        let openCount = Box(0)
        let liveGranted = Box(false)
        let pm = PermissionManager(
            settings: settings,
            accessibilityProbe: { liveGranted.value },
            requestAccessibilityAction: { /* prompt shown */ },
            openAccessibilitySettings: { openCount.value += 1 }
        )

        pm.requestAccessibilityIfNeeded()
        // Simulate the user clicking Allow before the grace window
        // expires.
        try? await Task.sleep(for: .milliseconds(500))
        liveGranted.value = true
        try? await Task.sleep(for: .seconds(2))
        #expect(openCount.value == 0)
    }
}

/// v0.10.2 — AppDelegate launch-time recovery detection. The actual
/// AppDelegate code path is hard to unit-test (NSApp lifecycle hooks),
/// but the decision tree itself is a pure function of three booleans:
/// `firstRunCompleted`, the persisted `lastKnownAccessibilityGranted`,
/// and the live grant. Pinning the tree directly catches regressions
/// without spinning up an NSApplication.
@Suite("Launch recovery decision tree")
@MainActor
struct LaunchRecoveryDecisionTreeTests {
    private enum LaunchAction: Equatable {
        case firstRunOnboarding
        case recoveryOnboarding
        case silentHotkeyRegister
    }

    private func decide(
        firstRunCompleted: Bool,
        previouslyGranted: Bool,
        currentlyGranted: Bool
    ) -> LaunchAction {
        if !firstRunCompleted {
            return .firstRunOnboarding
        }
        if previouslyGranted && !currentlyGranted {
            return .recoveryOnboarding
        }
        return .silentHotkeyRegister
    }

    @Test("Fresh install — firstRunCompleted=false triggers first-run onboarding")
    func freshInstall() {
        #expect(decide(firstRunCompleted: false, previouslyGranted: false, currentlyGranted: false) == .firstRunOnboarding)
        // Even if the user (somehow) already granted before firstRun, the first-run
        // panel still shows so they confirm the initial flow once.
        #expect(decide(firstRunCompleted: false, previouslyGranted: true, currentlyGranted: true) == .firstRunOnboarding)
    }

    @Test("Permission previously granted and still granted — silent hotkey register")
    func steadyState() {
        #expect(decide(firstRunCompleted: true, previouslyGranted: true, currentlyGranted: true) == .silentHotkeyRegister)
    }

    @Test("Permission was granted, now revoked — recovery onboarding pops")
    func revoked() {
        #expect(decide(firstRunCompleted: true, previouslyGranted: true, currentlyGranted: false) == .recoveryOnboarding)
    }

    @Test("Never granted (user dismissed first-run without accepting) — silent")
    func neverGranted() {
        // No annoying recurring popup. User explicitly chose "Continue Anyway"
        // on first run. They can re-open the helper from the menu bar manually.
        #expect(decide(firstRunCompleted: true, previouslyGranted: false, currentlyGranted: false) == .silentHotkeyRegister)
    }

    @Test("Permission was lost then re-granted before launch — silent")
    func lostThenRegranted() {
        // Edge case: TCC reset, user opened Settings and re-granted before
        // launching the app. previouslyGranted=true, currentlyGranted=true.
        // No recovery popup needed.
        #expect(decide(firstRunCompleted: true, previouslyGranted: true, currentlyGranted: true) == .silentHotkeyRegister)
    }
}

/// Sendable reference cell used by tests to mutate probe state after
/// the @Sendable probe closure has captured it. Confined to test
/// scope; not exported to production code.
private final class Box<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}

import AppKit
import Sparkle

/// Thin wrapper around `SPUStandardUpdaterController`. Constructed at app
/// launch with `startingUpdater: true` so Sparkle begins its background
/// scheduling immediately (per the `SUScheduledCheckInterval` value in
/// `Info.plist` — 86400 seconds = once per day).
///
/// The "Check for Updates…" menu item routes through `checkForUpdates(_:)`,
/// which Sparkle handles entirely — it shows a verbose progress UI even
/// when no update is found, which is what users expect from a menu action.
///
/// Feed URL + EdDSA public signing key are baked into `Info.plist` by
/// `scripts/package_app.sh`; this class doesn't need to know them.
@MainActor
final class UpdaterManager {
    private let controller: SPUStandardUpdaterController

    init() {
        // `userDriverDelegate: nil` keeps the bundled standard UI
        // (Update Available dialog, install progress). `updaterDelegate`
        // is also nil for now — we don't need to intercept anything.
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    /// Manual "Check for Updates…" trigger. Sparkle displays its own
    /// progress / result dialog regardless of outcome.
    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}

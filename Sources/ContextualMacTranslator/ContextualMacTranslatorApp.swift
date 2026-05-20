import AppKit
import SwiftUI

/// SwiftUI App entry point. The legacy `NSApplication.shared` setup in this
/// file used to wire an `AppDelegate` manually and call `app.run()`. macOS 14
/// + SwiftUI's `@main App` + `MenuBarExtra` give us the same lifecycle in
/// roughly half the code, plus a declarative status-bar menu in place of the
/// imperative `NSStatusItem` we used to build by hand.
///
/// The `AppDelegate` is preserved via `@NSApplicationDelegateAdaptor` because
/// it still owns the global hotkey manager, the workflow, both HUD
/// controllers, and the onboarding + settings windows. Translation actions
/// are exposed via plain `@objc` methods on the delegate so the MenuBarExtra
/// buttons below can call them.
///
/// Activation policy stays `.accessory` because `LSUIElement=true` is set in
/// the bundle's `Info.plist`; no explicit `setActivationPolicy(.accessory)`
/// call is required.
@main
struct ContextualMacTranslatorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            AppMenuContent(appDelegate: appDelegate)
        } label: {
            Text("文")
        }
        .menuBarExtraStyle(.menu)
    }
}

/// Declarative SwiftUI menu for the status bar. Replaces the imperative
/// `NSMenu` previously constructed in `AppDelegate.buildStatusItem`.
private struct AppMenuContent: View {
    let appDelegate: AppDelegate

    var body: some View {
        Button("Translate Selection to Vietnamese  ⌥D") {
            appDelegate.translateSelection()
        }
        Button("Send Japanese Keigo  ⌘↩") {
            appDelegate.sendKeigo()
        }
        Button("Send Japanese Casual  ⌥↩") {
            appDelegate.sendCasual()
        }

        Divider()

        Button("Settings…") {
            appDelegate.openSettings()
        }
        .keyboardShortcut(",")
        Button("Request Permissions") {
            appDelegate.requestPermissions()
        }
        Button("First Launch Setup…") {
            appDelegate.openOnboarding()
        }

        Divider()

        Button("Quit Contextual Mac Translator") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

import AppKit
import Observation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var settingsWindowController: SettingsWindowController?
    private var onboardingWindowController: OnboardingWindowController?
    private var hotKeysRegistered = false
    private var isObservingBindings = false

    private lazy var permissionManager = PermissionManager()
    private lazy var hudController = HUDController()
    private lazy var previewHUDController = PreviewHUDController()
    private lazy var updaterManager = UpdaterManager()
    private lazy var providerFactory = TranslationProviderFactory(settings: .shared)
    private lazy var workflow = TranslationWorkflow(
        providerFactory: { [providerFactory] in providerFactory.make() },
        hudController: hudController,
        keyboard: KeyboardSimulator(),
        pasteboard: ClipboardService(),
        previewPresenter: previewHUDController
    )
    private lazy var hotKeyManager = HotKeyManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The menu bar status item is now owned by the SwiftUI MenuBarExtra
        // scene in `ContextualMacTranslatorApp` — we only set up the hidden
        // main menu (Edit submenu for Cmd-C/V/X responder chain in text
        // fields) and the post-launch flow here.
        buildMainMenu()
        // Touch the updater so its constructor runs and Sparkle's
        // background scheduler starts. Initial check is deferred by
        // Sparkle's own logic (it won't fire immediately on first launch).
        _ = updaterManager
        if SettingsStore.shared.firstRunCompleted {
            registerHotKeys()
        } else {
            showOnboarding()
        }
    }

    /// LSUIElement apps don't get a standard menu bar, so SwiftUI
    /// `TextField`/`SecureField` inside Settings + Onboarding windows
    /// have no `Cut/Copy/Paste/Undo` Cmd-shortcuts wired by default.
    /// Installing a minimal Edit menu via `NSApp.mainMenu` re-enables
    /// the system-standard responder-chain bindings even when the menu
    /// itself isn't visible (`LSUIElement` hides it from the menu bar).
    private func buildMainMenu() {
        let mainMenu = NSMenu()

        // App submenu — only need Quit; SwiftUI windows get the rest
        // via the responder chain.
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(
            title: "Quit Contextual Mac Translator",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))
        appMenuItem.submenu = appMenu

        // Edit submenu — the actual fix for Cmd-C/X/V/A in text fields.
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        let redoItem = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redoItem)
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(
            title: "Select All",
            action: #selector(NSText.selectAll(_:)),
            keyEquivalent: "a"
        ))
        editMenuItem.submenu = editMenu

        NSApp.mainMenu = mainMenu
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeyManager.unregisterAll()
    }

    /// Re-register all global hotkeys from the current settings. Safe to
    /// call repeatedly — `HotKeyManager.register` clears the previous set
    /// first. Also subscribes to `SettingsStore` binding changes the first
    /// time, so Settings UI edits re-register hotkeys automatically.
    func registerHotKeys() {
        applyHotKeys()
        observeBindingChangesIfNeeded()
    }

    private func observeBindingChangesIfNeeded() {
        guard !isObservingBindings else { return }
        isObservingBindings = true
        observeBindingsOnce()
    }

    /// Re-arming observation: `withObservationTracking` fires once and then
    /// stops, so the `onChange` callback re-registers the closure to keep
    /// observing future changes. This is the standard pattern with the
    /// Observation framework when you want continuous notifications.
    private func observeBindingsOnce() {
        let settings = SettingsStore.shared
        withObservationTracking {
            _ = settings.inboundBinding
            _ = settings.outboundBindings
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.applyHotKeys()
                self.observeBindingsOnce()
            }
        }
    }

    private func applyHotKeys() {
        let settings = SettingsStore.shared
        let outbound = settings.outboundBindings.map { binding -> (config: HotkeyConfig, action: @MainActor () -> Void) in
            let style = binding.style()
            return (
                config: binding.hotkey,
                action: { [weak self] in
                    Task { @MainActor in
                        await self?.workflow.translateAndSend(persona: style)
                    }
                }
            )
        }
        hotKeyManager.register(
            inbound: settings.inboundBinding.hotkey,
            inboundAction: { [weak self] in
                Task { @MainActor in
                    await self?.workflow.translateSelection()
                }
            },
            outbound: outbound
        )
        hotKeysRegistered = true
    }

    private func showOnboarding() {
        if onboardingWindowController == nil {
            onboardingWindowController = OnboardingWindowController(
                permissionManager: permissionManager,
                onContinue: { [weak self] in
                    SettingsStore.shared.firstRunCompleted = true
                    self?.onboardingWindowController?.close()
                    self?.registerHotKeys()
                }
            )
        }
        onboardingWindowController?.show()
    }

    @objc func translateSelection() {
        Task { @MainActor in
            await workflow.translateSelection()
        }
    }

    @objc func sendKeigo() {
        Task { @MainActor in
            // Status-bar fallback for first outbound binding marked formal.
            let style: TranslationStyle = SettingsStore.shared.outboundBindings.first(where: { $0.register == .formal })?.style() ?? .japaneseBusiness
            await workflow.translateAndSend(persona: style)
        }
    }

    @objc func sendCasual() {
        Task { @MainActor in
            let style: TranslationStyle = SettingsStore.shared.outboundBindings.first(where: { $0.register == .casual })?.style() ?? .japaneseCasual
            await workflow.translateAndSend(persona: style)
        }
    }

    @objc func openSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(permissionManager: permissionManager)
        }
        settingsWindowController?.show()
    }

    @objc func requestPermissions() {
        permissionManager.requestAccessibilityIfNeeded()
        permissionManager.requestInputMonitoringIfNeeded()
    }

    @objc func openOnboarding() {
        showOnboarding()
    }

    @objc func checkForUpdates() {
        updaterManager.checkForUpdates()
    }

    @objc func quit() {
        NSApplication.shared.terminate(nil)
    }
}

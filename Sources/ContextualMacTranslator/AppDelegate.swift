import AppKit
import Observation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var settingsWindowController: SettingsWindowController?
    private var onboardingWindowController: OnboardingWindowController?
    private var whatsNewWindowController: WhatsNewWindowController?
    private var hotKeysRegistered = false
    private var isObservingBindings = false

    private lazy var permissionManager = PermissionManager()
    private lazy var hudController = HUDController()
    private lazy var previewHUDController = PreviewHUDController()
    // v0.8.4 — eager (not lazy) so the NSPanel is constructed at app
    // launch, paying the ~30-60ms setup cost off the hotkey path. First
    // picker press is then near-instant (just a positioning + orderFront).
    private let tonePickerController = TonePickerController()
    private lazy var updaterManager = UpdaterManager()
    private lazy var providerFactory = TranslationProviderFactory(settings: .shared)
    private lazy var workflow = TranslationWorkflow(
        providerFactory: { [providerFactory] in providerFactory.make() },
        hudController: hudController,
        keyboard: KeyboardSimulator(),
        pasteboard: ClipboardService(),
        previewPresenter: previewHUDController,
        pickerPresenter: tonePickerController
    )
    private lazy var hotKeyManager = HotKeyManager()

    /// v0.9.0 — install the running workflow into the global router so
    /// App Intents (which the system constructs outside our DI graph)
    /// have something to call into. Must run before the first intent
    /// could fire, so we wire it at the very top of launch.
    private func installAppIntentRouter() {
        TranslationIntentRouter.shared.install(workflow)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        installAppIntentRouter()
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
        // v0.9.0 — show the What's-New window on a fresh minor/major.
        // Deferred slightly so it doesn't trample the onboarding flow
        // (which only fires when firstRunCompleted is false, so this is
        // belt-and-braces — both can't fire on the same launch anyway).
        if SettingsStore.shared.firstRunCompleted {
            maybeShowWhatsNew()
        }
    }

    /// Compare the bundled CFBundleShortVersionString against the last
    /// version we showed the What's-New window for. If they differ
    /// (typical case: user just upgraded), pop the window once and
    /// record the version so it stays dismissed next launch.
    private func maybeShowWhatsNew() {
        let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let lastShown = SettingsStore.shared.lastShownWhatsNewVersion
        guard !current.isEmpty, current != lastShown else { return }
        // Only show for v0.9.x for now — earlier copy lives behind a
        // version gate so a v0.10.0 upgrade can swap to a new highlight
        // set without re-showing the v0.9.0 one.
        guard current.hasPrefix("0.9.") else {
            SettingsStore.shared.lastShownWhatsNewVersion = current
            return
        }
        let controller = WhatsNewWindowController(
            version: current,
            highlights: WhatsNewWindowController.v0_9_0Highlights,
            onContinue: { [weak self] in
                SettingsStore.shared.lastShownWhatsNewVersion = current
                self?.whatsNewWindowController?.close()
                self?.whatsNewWindowController = nil
            }
        )
        whatsNewWindowController = controller
        controller.show()
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
            _ = settings.rewriteBindings
            _ = settings.pickerHotkey
            _ = settings.captureHotkey
            // Provider/source changes also affect whether rewrite hotkeys
            // get registered (see `rewriteAvailable` gate in `applyHotKeys`).
            _ = settings.translationSource
            _ = settings.directProvider
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
        var outbound = settings.outboundBindings.map { binding -> (config: HotkeyConfig, action: @MainActor () -> Void) in
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
        // Rewrite bindings register only when the active provider can
        // actually rewrite — otherwise the hotkey would just fire and pop
        // an error every time. Switching back to an LLM provider triggers
        // a re-register via `observeBindingsOnce` so the hotkey returns.
        // v0.9.0 — OCR capture hotkey. Gated on the active provider
        // being configured (any translator works — OCR doesn't require
        // LLM-class). User explicitly assigns the hotkey in Settings;
        // unset = OCR disabled.
        if let captureHotkey = settings.captureHotkey {
            outbound.append((
                config: captureHotkey,
                action: { [weak self] in
                    Task { @MainActor in
                        await self?.workflow.captureAndTranslate()
                    }
                }
            ))
        }

        if settings.rewriteAvailable {
            let rewriteEntries = settings.rewriteBindings.map { binding -> (config: HotkeyConfig, action: @MainActor () -> Void) in
                (
                    config: binding.hotkey,
                    action: { [weak self] in
                        Task { @MainActor in
                            await self?.workflow.rewriteAndSend(binding: binding)
                        }
                    }
                )
            }
            outbound.append(contentsOf: rewriteEntries)

            // Tone picker hotkey (v0.8) — re-press while the picker is
            // already on screen toggles it closed instead of capturing a
            // second line. Same `rewriteAvailable` gate as bindings.
            if let pickerHotkey = settings.pickerHotkey {
                outbound.append((
                    config: pickerHotkey,
                    action: { [weak self] in
                        Task { @MainActor in
                            guard let self else { return }
                            if self.tonePickerController.isShowing {
                                self.tonePickerController.dismissIfShowing()
                            } else {
                                await self.workflow.rewriteWithPickerAndSend()
                            }
                        }
                    }
                ))
            }
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

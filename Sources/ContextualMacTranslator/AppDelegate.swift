import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var settingsWindowController: SettingsWindowController?
    private var onboardingWindowController: OnboardingWindowController?
    private var hotKeysRegistered = false

    private lazy var permissionManager = PermissionManager()
    private lazy var hudController = HUDController()
    private lazy var previewHUDController = PreviewHUDController()
    private lazy var translator = TranslatorAPI(settings: .shared)
    private lazy var workflow = TranslationWorkflow(
        translator: translator,
        hudController: hudController,
        keyboard: KeyboardSimulator(),
        pasteboard: ClipboardService(),
        previewPresenter: previewHUDController
    )
    private lazy var hotKeyManager = HotKeyManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildStatusItem()
        if SettingsStore.shared.firstRunCompleted {
            registerHotKeys()
        } else {
            showOnboarding()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeyManager.unregisterAll()
    }

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.title = "文"

        let menu = NSMenu()
        menu.addItem(NSMenuItem(
            title: "Translate Selection to Vietnamese    Option-D",
            action: #selector(translateSelection),
            keyEquivalent: ""
        ))
        menu.addItem(NSMenuItem(
            title: "Send Japanese Keigo    Command-Return",
            action: #selector(sendKeigo),
            keyEquivalent: ""
        ))
        menu.addItem(NSMenuItem(
            title: "Send Japanese Casual    Option-Return",
            action: #selector(sendCasual),
            keyEquivalent: ""
        ))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: "Settings...",
            action: #selector(openSettings),
            keyEquivalent: ","
        ))
        menu.addItem(NSMenuItem(
            title: "Request Permissions",
            action: #selector(requestPermissions),
            keyEquivalent: ""
        ))
        menu.addItem(NSMenuItem(
            title: "First Launch Setup...",
            action: #selector(openOnboarding),
            keyEquivalent: ""
        ))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: "Quit",
            action: #selector(quit),
            keyEquivalent: "q"
        ))

        menu.items.forEach { $0.target = self }
        item.menu = menu
        statusItem = item
    }

    private func registerHotKeys() {
        guard !hotKeysRegistered else { return }
        hotKeyManager.onInbound = { [weak self] in
            Task { @MainActor in
                await self?.workflow.translateSelection()
            }
        }
        hotKeyManager.onOutboundKeigo = { [weak self] in
            Task { @MainActor in
                await self?.workflow.translateAndSend(persona: .japaneseBusiness)
            }
        }
        hotKeyManager.onOutboundCasual = { [weak self] in
            Task { @MainActor in
                await self?.workflow.translateAndSend(persona: .japaneseCasual)
            }
        }
        hotKeyManager.registerDefaults()
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

    @objc private func translateSelection() {
        Task { @MainActor in
            await workflow.translateSelection()
        }
    }

    @objc private func sendKeigo() {
        Task { @MainActor in
            await workflow.translateAndSend(persona: .japaneseBusiness)
        }
    }

    @objc private func sendCasual() {
        Task { @MainActor in
            await workflow.translateAndSend(persona: .japaneseCasual)
        }
    }

    @objc private func openSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(permissionManager: permissionManager)
        }
        settingsWindowController?.show()
    }

    @objc private func requestPermissions() {
        permissionManager.requestAccessibilityIfNeeded()
        permissionManager.requestInputMonitoringIfNeeded()
    }

    @objc private func openOnboarding() {
        showOnboarding()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}

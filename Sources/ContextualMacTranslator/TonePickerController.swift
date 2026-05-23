import AppKit
import SwiftUI

/// Protocol so `TranslationWorkflow` can stub the picker in tests.
@MainActor
protocol TonePickerPresenter: AnyObject {
    /// Show the picker and resolve with the chosen entry — either a
    /// preset tone or the user's free-text instruction — or `nil` if
    /// the user cancelled (Esc, click-outside, focus loss, dwell timeout).
    func present(isSourceFocused: @escaping @MainActor () -> Bool) async -> PickerEntry?

    /// Synchronous close (toggle support: re-pressing the picker hotkey
    /// while the picker is on screen dismisses it).
    func dismissIfShowing()

    /// `true` when the picker panel is currently on screen — read by the
    /// AppDelegate hotkey handler to choose between present and dismiss.
    var isShowing: Bool { get }
}

/// Floating tone picker — clone of `PreviewHUDController` patterns:
/// non-activating panel, click-outside / focus-loss / dwell timeouts,
/// idempotent commit through `TonePickerViewModel.onCommit`.
@MainActor
final class TonePickerController: TonePickerPresenter {
    private var panel: PickerPanel?
    private var hostingController: NSHostingController<TonePickerView>?
    private var focusMonitorTask: Task<Void, Never>?
    private var dwellTask: Task<Void, Never>?
    private var clickMonitor: Any?
    private weak var currentModel: TonePickerViewModel?

    /// Single source of truth for the picker panel's content size — used
    /// at NSPanel construction AND during cursor-anchored positioning so
    /// the two can never drift.
    private let panelSize = NSSize(width: 360, height: 340)

    private let focusLossTimeout: Duration
    private let focusPollInterval: Duration
    private let dwellTimeout: Duration

    init(
        focusLossTimeout: Duration = .seconds(5),
        focusPollInterval: Duration = .milliseconds(250),
        dwellTimeout: Duration = .seconds(20)
    ) {
        self.focusLossTimeout = focusLossTimeout
        self.focusPollInterval = focusPollInterval
        self.dwellTimeout = dwellTimeout
        // v0.8.4 — pre-warm the panel at init so the first hotkey press
        // doesn't pay the NSPanel construction cost (~30-60ms). The panel
        // is created off-screen and only `orderFront`'d in `show()`.
        self.panel = makePanel()
    }

    var isShowing: Bool {
        panel?.isVisible == true
    }

    func present(isSourceFocused: @escaping @MainActor () -> Bool) async -> PickerEntry? {
        await withCheckedContinuation { continuation in
            show(isSourceFocused: isSourceFocused, continuation: continuation)
        }
    }

    func dismissIfShowing() {
        // Route through the model so the awaiting continuation resolves
        // with `nil` (cancel) — never just `orderOut` the panel, that
        // would leak the continuation.
        guard isShowing, let model = currentModel else { return }
        model.commit(nil)
    }

    // MARK: - Private

    private func show(
        isSourceFocused: @escaping @MainActor () -> Bool,
        continuation: CheckedContinuation<PickerEntry?, Never>
    ) {
        // Filter the visible tones by the expressive opt-in toggle so
        // "Chửi thề" (casual-raw) only appears for users who explicitly
        // enabled it in Settings.
        let items = RewriteTone.available(expressive: SettingsStore.shared.expressiveTonesEnabled)
        // v0.8.4 — also surface persisted RewriteBindings whose owner
        // ticked "In picker" so they can be picked from the popup
        // without remembering the hotkey.
        let pickerBindings = SettingsStore.shared.rewriteBindings.filter { $0.showInPicker }
        let model = TonePickerViewModel(items: items, bindings: pickerBindings)
        currentModel = model

        // `resolved` guards against double-resume — every dismissal path
        // (commit, focus loss, dwell, click-outside) funnels through here.
        var resolved = false
        let resolve: @MainActor (PickerEntry?) -> Void = { [weak self] entry in
            guard !resolved else { return }
            resolved = true
            self?.close()
            continuation.resume(returning: entry)
        }

        model.onCommit = { entry in resolve(entry) }

        let panel = panel ?? makePanel()
        panel.onKey = { [weak model] key in model?.handle(key) ?? false }

        let hostingController = NSHostingController(rootView: TonePickerView(model: model))
        hostingController.sizingOptions = .minSize
        panel.contentViewController = hostingController
        self.panel = panel
        self.hostingController = hostingController

        positionAtCursor(panel: panel)
        // makeKeyAndOrderFront on a `.nonactivatingPanel` puts the panel
        // on screen AND gives it key status WITHOUT activating our app —
        // the source app stays frontmost so the eventual paste lands
        // there. Never call NSApp.activate in this path.
        panel.makeKeyAndOrderFront(nil)

        installClickOutsideMonitor(resolve: resolve)
        startFocusMonitor(isSourceFocused: isSourceFocused, resolve: resolve)
        startDwellTimer(resolve: resolve)
    }

    private func close() {
        focusMonitorTask?.cancel()
        focusMonitorTask = nil
        dwellTask?.cancel()
        dwellTask = nil
        uninstallClickOutsideMonitor()
        panel?.orderOut(nil)
        // Drop our strong ref to the hosting controller. The panel's
        // `contentViewController` setter on the next `show()` already
        // releases the previous one through AppKit's VC lifecycle; nilling
        // here is defensive cleanup so a long idle period doesn't keep
        // the old SwiftUI view tree alive via two retain paths.
        hostingController = nil
        currentModel = nil
    }

    /// Dismiss when the user clicks in another app (the global monitor
    /// only fires on events sent to OTHER processes — clicks inside the
    /// picker hit SwiftUI handlers via the panel directly).
    private func installClickOutsideMonitor(resolve: @escaping @MainActor (PickerEntry?) -> Void) {
        uninstallClickOutsideMonitor()
        clickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { _ in
            Task { @MainActor in resolve(nil) }
        }
    }

    private func uninstallClickOutsideMonitor() {
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }
    }

    private func startFocusMonitor(
        isSourceFocused: @escaping @MainActor () -> Bool,
        resolve: @escaping @MainActor (PickerEntry?) -> Void
    ) {
        focusMonitorTask?.cancel()
        focusMonitorTask = Task { @MainActor [focusLossTimeout, focusPollInterval] in
            var lostSince: ContinuousClock.Instant?
            while !Task.isCancelled {
                if isSourceFocused() {
                    lostSince = nil
                } else {
                    let now = ContinuousClock.now
                    if lostSince == nil {
                        lostSince = now
                    }
                    if let since = lostSince, since.duration(to: now) >= focusLossTimeout {
                        resolve(nil)
                        return
                    }
                }
                try? await Task.sleep(for: focusPollInterval)
            }
        }
    }

    /// Hard timeout — even if focus is preserved, an abandoned picker
    /// auto-dismisses after `dwellTimeout` so it doesn't sit forever.
    private func startDwellTimer(resolve: @escaping @MainActor (PickerEntry?) -> Void) {
        dwellTask?.cancel()
        dwellTask = Task { @MainActor [dwellTimeout] in
            try? await Task.sleep(for: dwellTimeout)
            guard !Task.isCancelled else { return }
            resolve(nil)
        }
    }

    private func makePanel() -> PickerPanel {
        let panel = PickerPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = false
        // Required for the SwiftUI TextField (type-to-filter) to receive
        // key events — without this, the panel only becomes key when an
        // AppKit control "needs" it, which SwiftUI text inputs don't trigger.
        panel.becomesKeyOnlyIfNeeded = false
        panel.isFloatingPanel = true
        return panel
    }

    /// Anchor near the mouse cursor on whichever screen it's on, with a
    /// 16pt inset from every visible-frame edge. Flips above the cursor
    /// when there is no room below.
    private func positionAtCursor(panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let inset: CGFloat = 16

        // Default: below-and-right of the cursor.
        var origin = NSPoint(x: mouse.x + 8, y: mouse.y - panelSize.height - 8)

        // Horizontal clamp.
        if origin.x + panelSize.width > visible.maxX - inset {
            origin.x = visible.maxX - panelSize.width - inset
        }
        if origin.x < visible.minX + inset {
            origin.x = visible.minX + inset
        }
        // Vertical: flip above the cursor when below would clip.
        if origin.y < visible.minY + inset {
            origin.y = mouse.y + 18
        }
        if origin.y + panelSize.height > visible.maxY - inset {
            origin.y = visible.maxY - panelSize.height - inset
        }

        panel.setFrame(NSRect(origin: origin, size: panelSize), display: true)
    }
}

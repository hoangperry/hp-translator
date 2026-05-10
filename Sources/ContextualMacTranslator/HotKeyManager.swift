import Carbon.HIToolbox
import Foundation

/// Generic global hotkey manager backed by Carbon `RegisterEventHotKey`.
///
/// v0.3 refactor: instead of three hardcoded callbacks (`onInbound`,
/// `onOutboundKeigo`, `onOutboundCasual`), the manager now accepts a
/// dynamic list of `Registration`s. Each registration carries a
/// `HotkeyConfig` + an action closure. Re-registering replaces the
/// previous set so Settings changes apply on demand.
@MainActor
final class HotKeyManager {
    /// One global hotkey + the action to fire when it's pressed.
    struct Registration {
        let id: UInt32
        let config: HotkeyConfig
        let action: @MainActor () -> Void
    }

    private var handler: EventHandlerRef?
    private var registeredRefs: [(EventHotKeyRef, UInt32)] = []
    private var actions: [UInt32: @MainActor () -> Void] = [:]

    private static let signature = OSType(0x43545854) // "CTXT"

    /// Replace the current hotkey set with `registrations`. Caller is
    /// responsible for assigning unique non-zero IDs.
    func register(_ registrations: [Registration]) {
        unregisterAll()
        installHandlerIfNeeded()
        for reg in registrations {
            registerOne(id: reg.id, config: reg.config, action: reg.action)
        }
    }

    /// Convenience: assigns sequential IDs starting at 1 (inbound) then
    /// 2..N (outbound bindings in declaration order).
    func register(
        inbound: HotkeyConfig,
        inboundAction: @escaping @MainActor () -> Void,
        outbound: [(config: HotkeyConfig, action: @MainActor () -> Void)]
    ) {
        var registrations: [Registration] = []
        registrations.append(.init(id: 1, config: inbound, action: inboundAction))
        for (index, entry) in outbound.enumerated() {
            registrations.append(.init(
                id: UInt32(2 + index),
                config: entry.config,
                action: entry.action
            ))
        }
        register(registrations)
    }

    func unregisterAll() {
        registeredRefs.forEach { UnregisterEventHotKey($0.0) }
        registeredRefs.removeAll()
        actions.removeAll()

        if let handler {
            RemoveEventHandler(handler)
            self.handler = nil
        }
    }

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }

        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetApplicationEventTarget(),
            hotKeyEventHandler,
            1,
            &eventSpec,
            Unmanaged.passUnretained(self).toOpaque(),
            &handler
        )
    }

    private func registerOne(id: UInt32, config: HotkeyConfig, action: @escaping @MainActor () -> Void) {
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            config.keyCode,
            config.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if status == noErr, let ref {
            registeredRefs.append((ref, id))
            actions[id] = action
        }
    }

    fileprivate func handle(id: UInt32) {
        actions[id]?()
    }
}

private let hotKeyEventHandler: EventHandlerUPP = { _, event, userData in
    guard let event, let userData else { return noErr }

    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else { return status }

    let rawPointer = UInt(bitPattern: userData)
    let id = hotKeyID.id
    Task { @MainActor in
        guard let pointer = UnsafeRawPointer(bitPattern: rawPointer) else { return }
        let manager = Unmanaged<HotKeyManager>.fromOpaque(pointer).takeUnretainedValue()
        manager.handle(id: id)
    }
    return noErr
}

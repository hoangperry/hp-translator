import Carbon.HIToolbox
import Foundation

@MainActor
final class HotKeyManager {
    var onInbound: (() -> Void)?
    var onOutboundKeigo: (() -> Void)?
    var onOutboundCasual: (() -> Void)?

    private var handler: EventHandlerRef?
    private var registeredRefs: [EventHotKeyRef] = []

    private enum HotKeyID: UInt32 {
        case inbound = 1
        case outboundKeigo = 2
        case outboundCasual = 3
    }

    private static let signature = OSType(0x43545854) // CTXT

    func registerDefaults() {
        installHandlerIfNeeded()
        register(id: .inbound, keyCode: kVK_ANSI_D, modifiers: optionKey)
        register(id: .outboundKeigo, keyCode: kVK_Return, modifiers: cmdKey)
        register(id: .outboundCasual, keyCode: kVK_Return, modifiers: optionKey)
    }

    func unregisterAll() {
        registeredRefs.forEach { UnregisterEventHotKey($0) }
        registeredRefs.removeAll()

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

    private func register(id: HotKeyID, keyCode: Int, modifiers: Int) {
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id.rawValue)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(keyCode),
            UInt32(modifiers),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if status == noErr, let ref {
            registeredRefs.append(ref)
        }
    }

    fileprivate func handle(id: UInt32) {
        switch HotKeyID(rawValue: id) {
        case .inbound:
            onInbound?()
        case .outboundKeigo:
            onOutboundKeigo?()
        case .outboundCasual:
            onOutboundCasual?()
        case .none:
            break
        }
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

import Carbon.HIToolbox
import CoreGraphics
import Foundation

@MainActor
final class KeyboardSimulator {
    private let source = CGEventSource(stateID: .hidSystemState)

    func copySelection() async {
        press(keyCode: CGKeyCode(kVK_ANSI_C), flags: .maskCommand)
        await pause(milliseconds: 140)
    }

    func selectCurrentLineToBeginning() async {
        press(keyCode: CGKeyCode(kVK_LeftArrow), flags: [.maskCommand, .maskShift])
        await pause(milliseconds: 100)
    }

    func paste() async {
        press(keyCode: CGKeyCode(kVK_ANSI_V), flags: .maskCommand)
        await pause(milliseconds: 120)
    }

    func enter() async {
        press(keyCode: CGKeyCode(kVK_Return), flags: [])
        await pause(milliseconds: 80)
    }

    private func press(keyCode: CGKeyCode, flags: CGEventFlags) {
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        down?.flags = flags
        down?.post(tap: .cghidEventTap)

        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        up?.flags = flags
        up?.post(tap: .cghidEventTap)
    }

    private func pause(milliseconds: UInt64) async {
        try? await Task.sleep(for: .milliseconds(milliseconds))
    }
}

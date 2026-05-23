import ApplicationServices
import Foundation

/// Coarse classification of the currently-focused UI element across the
/// whole system. We use this *only* to refuse paste into password fields
/// before the rewrite even starts — the existing keyboard-simulation
/// path handles every other case the same way.
enum FocusedElementKind: Equatable, Sendable {
    /// A regular text input (NSTextField, NSTextView, most web inputs).
    case textInput
    /// A secure text input — password fields. Rewriting here would leak
    /// the (former) password into LLM provider logs.
    case secureTextInput
    /// Something else entirely — Finder selection, a button, a static
    /// label, etc. Capturing the line via Shift+Home + Cmd+C would
    /// produce noise or nothing; the workflow can still proceed but it
    /// usually short-circuits on the empty-clipboard check.
    case other
    /// AX inspection failed — usually means Accessibility permission was
    /// revoked, or the frontmost app does not implement AX properly.
    /// Treated as "proceed" by the workflow because the existing
    /// keyboard-simulation path would have failed first if there was no
    /// permission at all.
    case unknown
}

/// Reads the system-wide focused UI element's AX role. Cheap (one AX
/// round-trip) so safe to call on the hotkey hot path.
@MainActor
final class FocusedElementInspector {
    init() {}

    func currentKind() -> FocusedElementKind {
        guard AXIsProcessTrusted() else { return .unknown }
        let systemWide = AXUIElementCreateSystemWide()

        var focused: CFTypeRef?
        let focusErr = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focused
        )
        guard focusErr == .success, let element = focused else { return .unknown }
        // Force-cast is safe: `kAXFocusedUIElementAttribute` always
        // returns an AXUIElement when the error is `.success`.
        let axElement = unsafeDowncast(element, to: AXUIElement.self)

        var role: CFTypeRef?
        let roleErr = AXUIElementCopyAttributeValue(
            axElement,
            kAXRoleAttribute as CFString,
            &role
        )
        guard roleErr == .success, let roleStr = role as? String else { return .unknown }
        return Self.kind(forRole: roleStr)
    }

    /// Pure mapping from an AX role string to our coarse enum. Public-ish
    /// (internal) so tests can verify the role table without poking AX.
    nonisolated static func kind(forRole role: String) -> FocusedElementKind {
        // AX role strings are stable Apple-defined constants. The
        // `kAX…Role` symbols are NSAccessibility role enums in newer
        // SDKs; using string literals keeps us robust across the
        // CFString-vs-Swift-String typing drift between SDK versions.
        switch role {
        case "AXTextField", "AXTextArea", "AXComboBox":
            return .textInput
        case "AXSecureTextField":
            return .secureTextInput
        default:
            return .other
        }
    }
}

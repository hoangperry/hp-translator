import AppKit
import Foundation

struct ClipboardSnapshot {
    let items: [ClipboardItemSnapshot]
}

struct ClipboardItemSnapshot {
    let values: [NSPasteboard.PasteboardType: Data]
}

@MainActor
final class ClipboardService {
    private let pasteboard = NSPasteboard.general

    var changeCount: Int {
        pasteboard.changeCount
    }

    func capture() -> ClipboardSnapshot {
        let snapshots = (pasteboard.pasteboardItems ?? []).map { item in
            let values = item.types.reduce(into: [NSPasteboard.PasteboardType: Data]()) { result, type in
                if let data = item.data(forType: type) {
                    result[type] = data
                }
            }
            return ClipboardItemSnapshot(values: values)
        }
        return ClipboardSnapshot(items: snapshots)
    }

    func restore(_ snapshot: ClipboardSnapshot) {
        let items = snapshot.items.map { itemSnapshot in
            let item = NSPasteboardItem()
            itemSnapshot.values.forEach { type, data in
                item.setData(data, forType: type)
            }
            return item
        }
        pasteboard.clearContents()
        if !items.isEmpty {
            pasteboard.writeObjects(items)
        }
    }

    func writeString(_ value: String) {
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
    }

    /// Wait for the system pasteboard's `changeCount` to advance past
    /// `previousChangeCount`, indicating the user (or our synthetic Cmd+C)
    /// has placed new content. Returns `nil` if the change never happens
    /// within `timeout` — never returns the stale prior clipboard contents.
    func waitForCopiedString(
        after previousChangeCount: Int,
        timeout: Duration = .milliseconds(900)
    ) async -> String? {
        let pasteboard = self.pasteboard
        return await Self.pollForChange(
            previousChangeCount: previousChangeCount,
            currentChangeCount: { pasteboard.changeCount },
            currentString: { pasteboard.string(forType: .string) },
            timeout: timeout
        )
    }

    /// Pure polling logic exposed for unit tests; no AppKit references.
    /// Returns the new clipboard string when `changeCount` advances and
    /// the new value is non-empty (after trimming). Returns `nil` if the
    /// timeout elapses without a `changeCount` advance — protecting users
    /// from having stale clipboard contents (passwords, tokens, prior chat)
    /// silently sent to the LLM (security finding F-4).
    static func pollForChange(
        previousChangeCount: Int,
        currentChangeCount: @MainActor () -> Int,
        currentString: @MainActor () -> String?,
        timeout: Duration,
        sleep: @MainActor (Duration) async -> Void = { duration in
            try? await Task.sleep(for: duration)
        }
    ) async -> String? {
        let deadline = ContinuousClock.now + timeout
        let pollInterval: Duration = .milliseconds(40)

        repeat {
            let advanced = currentChangeCount() != previousChangeCount
            if advanced,
               let value = currentString(),
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value
            }
            await sleep(pollInterval)
        } while ContinuousClock.now < deadline

        // Final guard: if changeCount never advanced, refuse to return the
        // stale clipboard contents. This is the security-finding-F-4 fix.
        guard currentChangeCount() != previousChangeCount else {
            return nil
        }

        // Edge case: changeCount advanced but the read was racy — return
        // whatever is on the clipboard now, since at least it is fresh.
        if let late = currentString(),
           !late.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return late
        }
        return nil
    }
}

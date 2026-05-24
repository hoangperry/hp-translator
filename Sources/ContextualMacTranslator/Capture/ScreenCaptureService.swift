import AppKit
import Foundation

/// Result of a one-shot region capture. `nil`-equivalent (`cancelled`)
/// distinguishes "user pressed Escape" from "capture actually failed";
/// the workflow handles the two differently (silent vs. error toast).
enum ScreenCaptureResult: Sendable {
    case captured(CGImage)
    case cancelled
    case failed(String)
}

/// Protocol so the OCR workflow can be tested with a stubbed capture
/// surface (fixed image, fixed cancellation) without spawning the real
/// screen-region crosshair.
@MainActor
protocol ScreenCaptureService: AnyObject, Sendable {
    /// Show the OS region-selection crosshair and return the captured
    /// `CGImage`. Returns `.cancelled` when the user hits Escape, or
    /// `.failed(reason)` on any subprocess / decoding error.
    func captureRegion() async -> ScreenCaptureResult
}

/// Production implementation — shells out to the system
/// `/usr/sbin/screencapture` binary in interactive selection mode.
///
/// Why not `ScreenCaptureKit` (`SCContentSharingPicker` / `SCStream`)?
/// SCK is built for continuous capture (screen sharing, recording),
/// not one-shot region selection. We'd need a fullscreen transparent
/// `NSWindow` + custom mouse-drag overlay + manual pixel cropping —
/// hundreds of LOC of UX that has to match every Apple iteration of
/// the system crosshair UX. The system tool already IS that UX.
///
/// Permission posture: macOS prompts the user the first time the
/// system tool returns pixels to a process; the prompt is owned by
/// the OS, not by us. We declare `NSScreenCaptureUsageDescription` in
/// Info.plist as a safety net so the prompt has a meaningful reason
/// string when it appears.
@MainActor
final class SystemScreenCaptureService: ScreenCaptureService {
    /// Path to the system binary. Configurable for tests that want to
    /// substitute a fake.
    private let binary: String
    /// Detached-process timeout in seconds — if the user wanders off
    /// after triggering the hotkey, we don't leave the subprocess
    /// hanging forever (it blocks any future invocation).
    private let timeout: TimeInterval

    init(
        binary: String = "/usr/sbin/screencapture",
        timeout: TimeInterval = 60
    ) {
        self.binary = binary
        self.timeout = timeout
    }

    func captureRegion() async -> ScreenCaptureResult {
        // Run the subprocess off the main actor so the UI thread isn't
        // blocked while the user drags the crosshair.
        let binary = binary
        let timeout = timeout
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = Self.runCapture(binary: binary, timeout: timeout)
                continuation.resume(returning: result)
            }
        }
    }

    /// Synchronous capture invocation. Runs on a background queue from
    /// `captureRegion`. `nonisolated` so it escapes the class's
    /// `@MainActor` isolation and can be called from `DispatchQueue.global`.
    private nonisolated static func runCapture(binary: String, timeout: TimeInterval) -> ScreenCaptureResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        // `-i` interactive (crosshair / Escape cancels)
        // `-s` selection-only (skips the window picker)
        // `-x` mute the camera-shutter sound
        // `-t png` PNG output format
        // `-` write to stdout
        process.arguments = ["-i", "-s", "-x", "-t", "png", "-"]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            return .failed("Couldn't launch screencapture: \(error.localizedDescription)")
        }

        // Wait with a generous timeout — the user has to drag the
        // crosshair, which can take a while if they're picking text
        // from a paused video frame or a long page.
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning {
            if Date() > deadline {
                process.terminate()
                return .failed("Capture timed out after \(Int(timeout))s.")
            }
            Thread.sleep(forTimeInterval: 0.05)
        }

        // Exit 0 + bytes on stdout = success.
        // Exit 1 / no bytes = user cancelled (Esc).
        // The system tool doesn't emit a distinct exit code for the
        // two — we differentiate on stdout being non-empty.
        let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        guard !data.isEmpty else {
            return .cancelled
        }

        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            // Bytes came back but couldn't be decoded — surface a
            // useful error message rather than swallowing it.
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stderr = String(data: stderrData, encoding: .utf8) ?? ""
            return .failed("Couldn't decode captured PNG. \(stderr)")
        }

        return .captured(image)
    }
}

import Foundation

/// Stable per-install identity for SaaS device registration (M2.1-c).
///
/// `deviceID` is a UUID generated once and persisted in the Keychain — it
/// survives app reinstalls (Keychain outlives the app bundle), so a
/// reinstall reuses the same device slot rather than consuming a new one.
/// `deviceName` / `osVersion` are best-effort labels shown in the dashboard.
struct DeviceIdentity: Sendable, Equatable {
    let deviceID: String
    let deviceName: String
    let osVersion: String

    /// HTTP headers sent on signed cloud `/translate` requests so the
    /// backend can register the device and enforce the plan cap.
    var requestHeaders: [String: String] {
        [
            "X-Device-Id": deviceID,
            "X-Device-Name": deviceName,
            "X-Device-OS": osVersion,
        ]
    }
}

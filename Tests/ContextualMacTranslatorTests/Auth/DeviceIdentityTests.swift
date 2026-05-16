import Foundation
import Testing

@testable import ContextualMacTranslator

@Suite("DeviceIdentity")
struct DeviceIdentityTests {
    @Test("requestHeaders carries id, name, os under the X-Device-* keys")
    func requestHeaders() {
        let identity = DeviceIdentity(
            deviceID: "dev-123",
            deviceName: "Mai's MacBook",
            osVersion: "macOS 14.5"
        )
        let headers = identity.requestHeaders
        #expect(headers["X-Device-Id"] == "dev-123")
        #expect(headers["X-Device-Name"] == "Mai's MacBook")
        #expect(headers["X-Device-OS"] == "macOS 14.5")
    }
}

@Suite("SettingsStore.deviceIdentity")
@MainActor
struct SettingsStoreDeviceIdentityTests {
    private func makeSettings() -> SettingsStore {
        let suite = "device-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return SettingsStore(
            defaults: defaults,
            keychain: KeychainCredentialStore(service: "device-tests.\(UUID().uuidString)")
        )
    }

    @Test("deviceID is a valid UUID string")
    func deviceIDIsUUID() {
        let identity = makeSettings().deviceIdentity()
        #expect(UUID(uuidString: identity.deviceID) != nil)
    }

    @Test("deviceID is stable across calls — persisted in Keychain")
    func deviceIDStable() {
        let settings = makeSettings()
        let first = settings.deviceIdentity().deviceID
        let second = settings.deviceIdentity().deviceID
        #expect(first == second)
    }

    @Test("device name + os version are non-empty")
    func labelsPopulated() {
        let identity = makeSettings().deviceIdentity()
        #expect(!identity.deviceName.isEmpty)
        #expect(!identity.osVersion.isEmpty)
    }
}

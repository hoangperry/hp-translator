import Foundation

/// Endpoint scheme policy: HTTPS is required for remote hosts; HTTP is
/// only tolerated for loopback addresses (`localhost`, `127.0.0.1`, `::1`)
/// where the operator necessarily controls both endpoints of the
/// connection. Closes finding F-3 / FR-S3.
enum EndpointPolicy {
    static func allows(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else {
            return false
        }
        if scheme == "https" {
            return true
        }
        guard scheme == "http" else {
            return false
        }
        return isLoopbackHost(url.host)
    }

    /// Settings-UI hint shown beside the endpoint field when the value
    /// would be rejected by `allows(_:)`. Returns `nil` when the endpoint
    /// is empty (no hint yet) or already valid.
    static func warning(for endpoint: String) -> String? {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed) else {
            return nil
        }
        return allows(url) ? nil : "Remote endpoints must use HTTPS."
    }

    private static func isLoopbackHost(_ host: String?) -> Bool {
        switch host?.lowercased() {
        case "localhost", "127.0.0.1", "::1":
            return true
        default:
            return false
        }
    }
}

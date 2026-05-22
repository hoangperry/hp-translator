import Foundation
import Network
import OSLog

/// Minimal one-shot HTTP server bound to the loopback interface.
///
/// Captures the browser redirect at the end of the device-pairing flow:
/// the `/connect` web page redirects to `http://127.0.0.1:<port>/cb?code=…`,
/// this server reads that one request, hands back the query parameters, and
/// stops. Loopback-only — never reachable from the network.
final class LoopbackCallbackServer: @unchecked Sendable {
    enum LoopbackError: Error {
        case startFailed
        case timedOut
        case cancelled
    }

    private let listener: NWListener
    private let queue = DispatchQueue(label: "app.lookerlab.translator.loopback")
    private let logger = Logger(subsystem: "app.lookerlab.translator", category: "loopback")

    private var startContinuation: CheckedContinuation<UInt16, Error>?
    private var callbackContinuation: CheckedContinuation<[String: String], Error>?
    private var didStart = false
    private var didCallback = false

    init() throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        // Bind the loopback interface only — not reachable from the LAN.
        params.requiredInterfaceType = .loopback
        listener = try NWListener(using: params)
    }

    /// Start listening. Resolves with the OS-assigned ephemeral port.
    func start() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { cont in
            queue.async {
                self.startContinuation = cont
                self.listener.stateUpdateHandler = { [weak self] state in
                    guard let self else { return }
                    switch state {
                    case .ready:
                        guard !self.didStart else { return }
                        self.didStart = true
                        if let port = self.listener.port?.rawValue {
                            self.startContinuation?.resume(returning: port)
                        } else {
                            self.startContinuation?.resume(throwing: LoopbackError.startFailed)
                        }
                        self.startContinuation = nil
                    case .failed, .cancelled:
                        guard !self.didStart else { return }
                        self.didStart = true
                        self.startContinuation?.resume(throwing: LoopbackError.startFailed)
                        self.startContinuation = nil
                    default:
                        break
                    }
                }
                self.listener.newConnectionHandler = { [weak self] conn in
                    self?.handle(conn)
                }
                self.listener.start(queue: self.queue)
            }
        }
    }

    /// Suspend until the browser hits the callback URL. Returns its query
    /// parameters (e.g. `code`, `state`).
    func waitForCallback() async throws -> [String: String] {
        try await withCheckedThrowingContinuation { cont in
            queue.async {
                if self.didCallback {
                    cont.resume(throwing: LoopbackError.cancelled)
                    return
                }
                self.callbackContinuation = cont
            }
        }
    }

    /// Stop the listener. Safe to call multiple times.
    func stop() {
        queue.async {
            self.listener.cancel()
            if !self.didCallback {
                self.didCallback = true
                self.callbackContinuation?.resume(throwing: LoopbackError.cancelled)
                self.callbackContinuation = nil
            }
        }
    }

    // MARK: - Connection handling

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
            guard let self else { connection.cancel(); return }
            let query = data.flatMap { Self.parseQuery(from: $0) } ?? [:]
            self.respondAndClose(connection)
            self.deliver(query)
        }
    }

    /// Parse the query parameters out of the HTTP request line.
    /// Expects: `GET /cb?code=…&state=… HTTP/1.1`
    private static func parseQuery(from data: Data) -> [String: String]? {
        guard let text = String(data: data, encoding: .utf8),
              let firstLine = text.split(separator: "\r\n").first else {
            return nil
        }
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2, let target = parts[1].split(separator: "?").dropFirst().first else {
            return [:]
        }
        var result: [String: String] = [:]
        for pair in target.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            guard let key = kv.first else { continue }
            let value = kv.count > 1 ? String(kv[1]) : ""
            result[String(key)] = value.removingPercentEncoding ?? value
        }
        return result
    }

    private func respondAndClose(_ connection: NWConnection) {
        let body = """
        <!DOCTYPE html><html><head><meta charset="utf-8">
        <title>Contextual MT</title></head>
        <body style="font-family:-apple-system,sans-serif;text-align:center;padding:80px;color:#1a1a1a;">
        <h2>You're connected.</h2>
        <p style="color:#6b6b68;">Return to the Contextual MT app — you can close this tab.</p>
        </body></html>
        """
        let response = """
        HTTP/1.1 200 OK\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(body.utf8.count)\r
        Connection: close\r
        \r
        \(body)
        """
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func deliver(_ query: [String: String]) {
        guard !didCallback else { return }
        didCallback = true
        callbackContinuation?.resume(returning: query)
        callbackContinuation = nil
        listener.cancel()
    }
}

import Foundation
import Network

/// M3 backend: one local read-only HTTP service on 127.0.0.1 (never 0.0.0.0).
/// GET /health, /api/inbox, /api/services. No write routes: approving happens only in the app with Touch ID.
public final class LoopbackServer: @unchecked Sendable {
    public static let defaultPort = 9791
    public typealias Handler = @Sendable (String) async -> (Int, Data)
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "m3ta.console.backend")
    public let handler: Handler
    public init(handler: @escaping Handler) { self.handler = handler }

    /// Starts on 127.0.0.1:port (0 = ephemeral). Returns the bound port.
    public func start(port: Int = LoopbackServer.defaultPort) async throws -> Int {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: UInt16(port))!)
        params.allowLocalEndpointReuse = true
        let l = try NWListener(using: params)
        listener = l
        l.newConnectionHandler = { [weak self] c in self?.serve(c) }
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Int, Error>) in
            let once = OnceFlag()
            l.stateUpdateHandler = { st in
                switch st {
                case .ready: if once.fire() { cont.resume(returning: Int(l.port?.rawValue ?? 0)) }
                case .failed(let e): if once.fire() { cont.resume(throwing: e) }
                default: break
                }
            }
            l.start(queue: queue)
        }
    }
    public func stop() { listener?.cancel(); listener = nil }

    private func serve(_ c: NWConnection) {
        c.start(queue: queue)
        c.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [handler] data, _, _, _ in
            let req = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let first = req.split(separator: "\r\n").first?.split(separator: " ") ?? []
            Task {
                let (code, body): (Int, Data)
                if first.count >= 2, first[0] == "GET" { (code, body) = await handler(String(first[1])) }
                else { (code, body) = (405, Data(#"{"ok":false,"error":"read-only: GET only"}"#.utf8)) }
                let head = "HTTP/1.1 \(code) \(code == 200 ? "OK" : "ERR")\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
                c.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in c.cancel() })
            }
        }
    }
}

final class OnceFlag: @unchecked Sendable {
    private var done = false; private let l = NSLock()
    func fire() -> Bool { l.lock(); defer { l.unlock() }; if done { return false }; done = true; return true }
}

public enum ConsoleBackend {
    /// Route table for the loopback backend. Summaries only; no secrets are stored or returned.
    public static func handler(inbox: ApprovalInbox, health: HealthChecker) -> LoopbackServer.Handler {
        { path in
            func json(_ o: Any) -> Data { (try? JSONSerialization.data(withJSONObject: o, options: .sortedKeys)) ?? Data("{}".utf8) }
            switch path {
            case "/health": return (200, json(["ok": true, "service": "m3ta-os-console", "pending": inbox.pending().count]))
            case "/api/inbox": return (200, json(["pending": inbox.pending().map { ["hash": $0.hash, "tool": $0.tool, "kind": $0.kind, "at": $0.at] }]))
            case "/api/services":
                let r = await HealthChecker(specs: health.specs.filter { $0.id != "console-backend" }, prober: health.prober, log: health.log).checkAll()
                return (200, json(["services": r.map { ["id": $0.id, "up": $0.up, "detail": $0.detail, "restartable": $0.restartable] }]))
            default: return (404, json(["ok": false, "error": "not found"]))
            }
        }
    }
}

import Foundation

/// M3: talks to the root jevd over its unix socket (protocol from /usr/local/m3ta-jev/jevd.py):
/// send {"hash","approval"}\n, receive {"ok":true,"id"} or {"ok":false,"err"}. jevd keeps the
/// single-use ledger, so a signed approval can be consumed exactly once. Fails closed.
public enum GateResult: Sendable, Equatable { case pass(id: String), blocked(String) }

public protocol JEVConsumer: Sendable { func consume(hash: String, approval: String) -> GateResult }

public struct JEVSocketGate: JEVConsumer {
    public let socketPath: String
    public init(socketPath: String = ProcessInfo.processInfo.environment["REA_JEV_SOCK"] ?? "/var/run/m3ta-jev/jevd.sock") { self.socketPath = socketPath }
    public func consume(hash: String, approval: String) -> GateResult {
        guard ActionHash.valid(hash) else { return .blocked("JEV: bad hash") }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0); guard fd >= 0 else { return .blocked("JEV unreachable: socket()") }
        defer { close(fd) }
        var tv = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var addr = sockaddr_un(); addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(socketPath.utf8)
        guard pathBytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { return .blocked("JEV unreachable: path too long") }
        withUnsafeMutableBytes(of: &addr.sun_path) { b in for (i, x) in pathBytes.enumerated() { b[i] = x }; b[pathBytes.count] = 0 }
        let rc = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
        guard rc == 0 else { return .blocked("JEV unreachable at \(socketPath)") }
        guard let body = try? JSONSerialization.data(withJSONObject: ["hash": hash, "approval": approval]) else { return .blocked("JEV: encode") }
        let msg = body + Data("\n".utf8)
        let sent = msg.withUnsafeBytes { send(fd, $0.baseAddress, msg.count, 0) }
        guard sent == msg.count else { return .blocked("JEV unreachable: send") }
        var buf = [UInt8](repeating: 0, count: 4096); var got = Data()
        while !got.contains(0x0a) { let n = recv(fd, &buf, buf.count, 0); if n <= 0 { break }; got.append(contentsOf: buf[0..<n]) }
        guard let line = got.split(separator: 0x0a).first,
              let o = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else { return .blocked("JEV: no answer") }
        if o["ok"] as? Bool == true { return .pass(id: o["id"] as? String ?? "") }
        return .blocked("JEV refused: \(String(String(describing: o["err"] ?? "invalid").prefix(60)))")
    }
}

/// Runs a console-owned approved action at most once: approved in the ledger + a jevd pass
/// (single-use) are both required. The `executed` record is written before the side effect.
public struct ActionRunner: Sendable {
    public let inbox: ApprovalInbox; public let gate: JEVConsumer
    public init(inbox: ApprovalInbox, gate: JEVConsumer = JEVSocketGate()) { self.inbox = inbox; self.gate = gate }
    public enum Outcome: Sendable, Equatable { case ran, blocked(String) }
    public func run(_ h: String, now: Date = Date(), execute: @Sendable (HeldAction) -> Void) -> Outcome {
        guard let a = inbox.load(h), a.consoleOwned else { return .blocked("not a console action") }
        switch inbox.ledger.latest(h) {
        case .approved: break
        case .none: return .blocked("not approved")
        case .some(let d): return .blocked("already \(d.rawValue)")
        }
        guard let approval = try? String(contentsOf: inbox.paths.approvals.appending(path: "\(h).json"), encoding: .utf8) else { return .blocked("no signed approval file") }
        switch gate.consume(hash: h, approval: approval) {
        case .blocked(let why):
            try? inbox.ledger.append(.init(hash: h, decision: .blocked, at: Int(now.timeIntervalSince1970), note: why)) { $0 == .approved }
            return .blocked(why)
        case .pass(let id):
            let ok = (try? inbox.ledger.append(.init(hash: h, decision: .executed, at: Int(now.timeIntervalSince1970), note: "jevd id \(id.prefix(8))")) { $0 == .approved }) ?? false
            guard ok else { return .blocked("already run") }
            try? FileManager.default.moveItem(at: inbox.paths.approvals.appending(path: "\(h).json"), to: inbox.paths.approvals.appending(path: "\(h).json.used"))
            execute(a); return .ran
        }
    }
}

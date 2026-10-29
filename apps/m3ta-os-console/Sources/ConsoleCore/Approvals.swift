import Foundation
import CryptoKit

/// M3: approval inbox backed by JEV's own files (~/.config/m3ta/jev).
///  - pending/<hash>.json   held actions written by the JEV pre-tool hook (and by this console)
///  - approvals/<hash>.json Secure-Enclave-signed single-use approvals written by `jev-approve <hash>`
///  - console decisions     ~/Library/Application Support/M3taOSConsole/decisions.jsonl (append-only)
/// Approve = Touch ID (LocalAuthentication) + jev-approve signature. Deny = terminal, never runs.
public enum ActionHash {
    /// Same bytes as jev_pre_tool_hook.action_hash: sha256(json.dumps({"tool","input"}, sort_keys=True, separators=(",",":"))).
    /// ASCII-only inputs so Python's ensure_ascii and Swift agree byte-for-byte.
    public static func of(tool: String, input: [String: String]) throws -> String {
        let all = ([tool] + input.keys + input.values)
        guard all.allSatisfy({ $0.unicodeScalars.allSatisfy { $0.isASCII && $0.value >= 0x20 } }) else { throw InboxError.nonASCII }
        func q(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\"" }
        let inner = input.keys.sorted().map { "\(q($0)):\(q(input[$0]!))" }.joined(separator: ",")
        let canon = "{\"input\":{\(inner)},\"tool\":\(q(tool))}"
        return SHA256.hash(data: Data(canon.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    public static func valid(_ h: String) -> Bool { h.count == 64 && h.allSatisfy { "0123456789abcdef".contains($0) } }
}

public enum InboxError: Error, Equatable, CustomStringConvertible {
    case nonASCII, badHash, notPending, alreadyDecided(Decision), authFailed(String), signFailed(String)
    public var description: String {
        switch self {
        case .nonASCII: "Action input must be plain ASCII"
        case .badHash: "Not a valid action hash"
        case .notPending: "No held action with that hash"
        case .alreadyDecided(let d): "Already \(d.rawValue); decisions are final"
        case .authFailed(let w): "Touch ID failed: \(w)"
        case .signFailed(let w): "JEV signing failed: \(w)"
        }
    }
}

public enum Decision: String, Codable, Sendable { case approved, denied, executed, blocked }

public struct HeldAction: Codable, Identifiable, Sendable, Equatable {
    public var hash: String; public var tool: String; public var kind: String; public var summary: String; public var at: Int
    public var input: [String: String]?
    public var id: String { hash }
    public var consoleOwned: Bool { kind == "console" }
}

public struct DecisionRecord: Codable, Sendable, Equatable { public let hash: String; public let decision: Decision; public let at: Int; public let note: String }

public final class DecisionLedger: @unchecked Sendable {
    public let url: URL
    private let lock = NSLock()
    public init(url: URL) { self.url = url }
    public func all() -> [DecisionRecord] {
        guard let s = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return s.split(separator: "\n").compactMap { try? JSONDecoder().decode(DecisionRecord.self, from: Data($0.utf8)) }
    }
    public func latest(_ h: String) -> Decision? { all().last { $0.hash == h }?.decision }
    /// Append under a process lock + O_APPEND; returns false if `guardFn` rejects the current state (checked under the lock).
    @discardableResult
    public func append(_ r: DecisionRecord, guardFn: (Decision?) -> Bool = { _ in true }) throws -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard guardFn(latest(r.hash)) else { return false }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600]) }
        let fh = try FileHandle(forWritingTo: url); defer { try? fh.close() }
        try fh.seekToEnd(); try fh.write(contentsOf: JSONEncoder().encode(r) + Data("\n".utf8)); try fh.synchronize()
        return true
    }
}

public protocol Authenticator: Sendable { func authenticate(reason: String) async -> String? /* nil = success, else reason */ }
public protocol ApprovalSigner: Sendable { func sign(hash: String) async -> String? /* nil = success */ }

public struct JEVPaths: Sendable {
    public var root: URL
    public init(root: URL = URL(fileURLWithPath: NSHomeDirectory()).appending(path: ".config/m3ta/jev")) { self.root = root }
    public var pending: URL { root.appending(path: "pending") }
    public var approvals: URL { root.appending(path: "approvals") }
    public var approveBin: URL { root.appending(path: "bin/jev-approve") }
}

public struct ApprovalInbox: Sendable {
    public let paths: JEVPaths; public let ledger: DecisionLedger
    public init(paths: JEVPaths = .init(), ledger: DecisionLedger) { self.paths = paths; self.ledger = ledger }
    public static func defaultLedger() -> DecisionLedger {
        DecisionLedger(url: URL(fileURLWithPath: NSHomeDirectory()).appending(path: "Library/Application Support/M3taOSConsole/decisions.jsonl"))
    }

    /// Held actions that have no final decision yet, newest first.
    public func pending() -> [HeldAction] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: paths.pending.path) else { return [] }
        let decided = Dictionary(ledger.all().map { ($0.hash, $0.decision) }, uniquingKeysWith: { _, b in b })
        return names.filter { $0.hasSuffix(".json") }.compactMap { n -> HeldAction? in
            let h = String(n.dropLast(5)); guard ActionHash.valid(h), decided[h] == nil else { return nil }
            return load(h)
        }.sorted { $0.at > $1.at }
    }
    public func load(_ h: String) -> HeldAction? {
        guard let d = try? Data(contentsOf: paths.pending.appending(path: "\(h).json")),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
        let at = (o["at"] as? Int) ?? Int((o["at"] as? String) ?? "") ?? 0
        return HeldAction(hash: h, tool: o["tool"] as? String ?? "?", kind: o["kind"] as? String ?? "?",
                          summary: String((o["summary"] as? String ?? "").prefix(600)), at: at, input: o["input"] as? [String: String])
    }

    /// Hold a console-owned action (e.g. a service restart) so Kingdom must approve it.
    @discardableResult
    public func hold(tool: String, input: [String: String], now: Date = Date()) throws -> HeldAction {
        let h = try ActionHash.of(tool: tool, input: input)
        let a = HeldAction(hash: h, tool: tool, kind: "console", summary: input.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: " "), at: Int(now.timeIntervalSince1970), input: input)
        try FileManager.default.createDirectory(at: paths.pending, withIntermediateDirectories: true)
        try JSONEncoder().encode(a).write(to: paths.pending.appending(path: "\(h).json"), options: .atomic)
        return a
    }

    public func deny(_ h: String, note: String = "denied in console", now: Date = Date()) throws {
        guard ActionHash.valid(h) else { throw InboxError.badHash }
        guard load(h) != nil else { throw InboxError.notPending }
        var prior: Decision?
        let ok = try ledger.append(.init(hash: h, decision: .denied, at: Int(now.timeIntervalSince1970), note: note)) { prior = $0; return $0 == nil }
        if !ok { throw InboxError.alreadyDecided(prior!) }
        // A denied action never gets a signed approval; drop any stray unsigned approval file for it.
        try? FileManager.default.removeItem(at: paths.approvals.appending(path: "\(h).json"))
    }

    /// Touch ID, then the Secure-Enclave signature from jev-approve. Only then is the decision recorded.
    public func approve(_ h: String, auth: Authenticator, signer: ApprovalSigner, now: Date = Date()) async throws {
        guard ActionHash.valid(h) else { throw InboxError.badHash }
        guard let a = load(h) else { throw InboxError.notPending }
        if let d = ledger.latest(h) { throw InboxError.alreadyDecided(d) }
        if let why = await auth.authenticate(reason: "approve \(a.tool)") { throw InboxError.authFailed(why) }
        if let why = await signer.sign(hash: h) { throw InboxError.signFailed(why) }
        var prior: Decision?
        let ok = try ledger.append(.init(hash: h, decision: .approved, at: Int(now.timeIntervalSince1970), note: "Touch ID + jev-approve")) { prior = $0; return $0 == nil }
        if !ok { throw InboxError.alreadyDecided(prior!) }
    }
}

/// Runs `jev-approve <hash>` (its own Secure Enclave key prompts Touch ID / password) and answers its y/N prompt.
public struct JEVApproveSigner: ApprovalSigner {
    public let bin: URL
    public init(bin: URL = JEVPaths().approveBin) { self.bin = bin }
    public func sign(hash: String) async -> String? {
        guard ActionHash.valid(hash) else { return "bad hash" }
        guard FileManager.default.isExecutableFile(atPath: bin.path) else { return "jev-approve not found" }
        return await withCheckedContinuation { c in
            let p = Process(); p.executableURL = bin; p.arguments = [hash]
            let inp = Pipe(), err = Pipe(); p.standardInput = inp; p.standardOutput = FileHandle.nullDevice; p.standardError = err
            p.terminationHandler = { pr in
                let e = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                c.resume(returning: pr.terminationStatus == 0 ? nil : String(e.prefix(80)))
            }
            do { try p.run(); inp.fileHandleForWriting.write(Data("y\n".utf8)); try? inp.fileHandleForWriting.close() }
            catch { c.resume(returning: "could not start jev-approve") }
        }
    }
}

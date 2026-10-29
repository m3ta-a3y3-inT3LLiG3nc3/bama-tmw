import Foundation

/// M3: one health check across services. Probes are loopback-only GETs / socket checks.
/// Restarts are allowed only for Kingdom's own private launchd agents on an allowlist, never for
/// the protected set (JARVIS, Waypoint, Paperclip, Tailscale, Screenpipe, JEV), and only after an
/// approved + JEV-passed inbox action. Every check and restart is logged.
public struct ServiceSpec: Codable, Sendable, Identifiable, Equatable {
    public enum Probe: Codable, Sendable, Equatable { case http(port: Int, path: String), unixSocket(path: String), launchd }
    public var id: String; public var name: String; public var probe: Probe; public var launchdLabel: String?
    public init(id: String, name: String, probe: Probe, launchdLabel: String? = nil) { self.id = id; self.name = name; self.probe = probe; self.launchdLabel = launchdLabel }
}

public enum RestartPolicy {
    public static let ownPrefixes = ["com.m3ta.", "os.m3ta.", "com.th3m3taway."]
    public static let protectedWords = ["jarvis", "waypoint", "paperclip", "tailscale", "screenpipe", "jev", "console"]
    public static func canRestart(_ s: ServiceSpec) -> Bool {
        guard let l = s.launchdLabel?.lowercased(), ownPrefixes.contains(where: { l.hasPrefix($0) }) else { return false }
        let hay = (l + " " + s.id.lowercased() + " " + s.name.lowercased())
        return !protectedWords.contains { hay.contains($0) }
    }
}

public enum Services {
    public static let defaults: [ServiceSpec] = [
        .init(id: "jarvis-runtime", name: "JARVIS agent-runtime", probe: .http(port: 9782, path: "/health")),
        .init(id: "jarvis-rea", name: "JARVIS rea-mcp", probe: .http(port: 9783, path: "/health")),
        .init(id: "waypoint", name: "Waypoint", probe: .http(port: 3000, path: "/"), launchdLabel: "os.m3ta.waypoint"),
        .init(id: "jevd", name: "JEV daemon", probe: .unixSocket(path: "/var/run/m3ta-jev/jevd.sock")),
        .init(id: "ollama", name: "Ollama", probe: .http(port: 11434, path: "/api/version"), launchdLabel: "com.m3ta.ollama-host"),
        .init(id: "openai-oauth", name: "ChatGPT Pro relay", probe: .http(port: 10531, path: "/v1/models"), launchdLabel: "os.m3ta.openai-oauth"),
        .init(id: "openbot", name: "OpenBot (Orbit runner)", probe: .launchd, launchdLabel: "com.m3ta.openbot"),
        .init(id: "vaultmcp", name: "Vault MCP", probe: .launchd, launchdLabel: "com.m3ta.vaultmcp-http"),
        .init(id: "ether-inbox", name: "Ether inbox", probe: .launchd, launchdLabel: "com.m3ta.ether-inbox"),
        .init(id: "console-backend", name: "Console backend", probe: .http(port: LoopbackServer.defaultPort, path: "/health")),
    ]
}

public struct HealthResult: Codable, Sendable, Equatable, Identifiable {
    public let id: String; public let name: String; public let up: Bool; public let detail: String; public let restartable: Bool; public let at: Int
}

public protocol HealthProber: Sendable {
    func http(port: Int, path: String) async -> (Bool, String)
    func socketExists(_ path: String) -> Bool
    func launchdRunning(_ label: String) -> (Bool, String)
}

public struct LiveProber: HealthProber {
    public init() {}
    public func http(port: Int, path: String) async -> (Bool, String) {
        let c = URLSessionConfiguration.ephemeral; c.timeoutIntervalForRequest = 2; c.connectionProxyDictionary = [:]
        var r = URLRequest(url: URL(string: "http://127.0.0.1:\(port)\(path)")!); r.httpMethod = "GET"
        do { let (_, resp) = try await URLSession(configuration: c).data(for: r)
             let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
             return (200..<400 ~= code, "HTTP \(code) on 127.0.0.1:\(port)") }
        catch { return (false, "no answer on 127.0.0.1:\(port)") }
    }
    public func socketExists(_ path: String) -> Bool {
        var st = stat(); return stat(path, &st) == 0 && (st.st_mode & S_IFMT) == S_IFSOCK
    }
    public func launchdRunning(_ label: String) -> (Bool, String) {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/launchctl"); p.arguments = ["print", "gui/\(getuid())/\(label)"]
        let o = Pipe(); p.standardOutput = o; p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return (false, "launchctl failed") }
        let d = o.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
        let s = String(data: d, encoding: .utf8) ?? ""
        if p.terminationStatus != 0 { return (false, "not loaded") }
        let running = s.contains("state = running")
        return (running, running ? "launchd: running" : "launchd: loaded, not running")
    }
}

public final class HealthLog: @unchecked Sendable {
    public let url: URL; private let lock = NSLock()
    public init(url: URL = URL(fileURLWithPath: NSHomeDirectory()).appending(path: "Library/Logs/M3taOSConsole/health.jsonl")) { self.url = url }
    public func write(_ event: String, _ fields: [String: String]) {
        lock.lock(); defer { lock.unlock() }
        var o = fields; o["event"] = event; o["at"] = ISO8601DateFormatter().string(from: Date())
        guard let d = try? JSONSerialization.data(withJSONObject: o, options: .sortedKeys) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
        if let fh = try? FileHandle(forWritingTo: url) { _ = try? fh.seekToEnd(); try? fh.write(contentsOf: d + Data("\n".utf8)); try? fh.close() }
    }
}

public struct HealthChecker: Sendable {
    public let specs: [ServiceSpec]; public let prober: HealthProber; public let log: HealthLog
    public init(specs: [ServiceSpec] = Services.defaults, prober: HealthProber = LiveProber(), log: HealthLog = HealthLog()) { self.specs = specs; self.prober = prober; self.log = log }
    public func checkAll(now: Date = Date()) async -> [HealthResult] {
        var out: [HealthResult] = []
        for s in specs {
            let (up, detail): (Bool, String)
            switch s.probe {
            case .http(let port, let path): (up, detail) = await prober.http(port: port, path: path)
            case .unixSocket(let p): up = prober.socketExists(p); detail = up ? "socket present" : "socket missing"
            case .launchd: (up, detail) = s.launchdLabel.map { prober.launchdRunning($0) } ?? (false, "no label")
            }
            out.append(.init(id: s.id, name: s.name, up: up, detail: detail, restartable: RestartPolicy.canRestart(s), at: Int(now.timeIntervalSince1970)))
        }
        log.write("health_check", ["up": "\(out.filter(\.up).count)", "total": "\(out.count)", "down": out.filter { !$0.up }.map(\.id).joined(separator: ",")])
        return out
    }
    public static let restartTool = "console.restart_service"
    /// Holds a restart in the approval inbox; refuses anything off the allowlist.
    public func requestRestart(_ id: String, inbox: ApprovalInbox) throws -> HeldAction? {
        guard let s = specs.first(where: { $0.id == id }), RestartPolicy.canRestart(s), let l = s.launchdLabel else {
            log.write("restart_refused", ["service": id, "why": "not on the private-service allowlist"]); return nil
        }
        let a = try inbox.hold(tool: Self.restartTool, input: ["label": l])
        log.write("restart_held", ["service": id, "label": l, "hash": String(a.hash.prefix(12))]); return a
    }
    /// The side effect run by ActionRunner after approval + jevd pass. Re-checks the allowlist.
    public func performRestart(_ a: HeldAction) {
        guard a.tool == Self.restartTool, let l = a.input?["label"], let s = specs.first(where: { $0.launchdLabel == l }), RestartPolicy.canRestart(s) else {
            log.write("restart_refused", ["hash": String(a.hash.prefix(12)), "why": "label not allowlisted"]); return
        }
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/launchctl"); p.arguments = ["kickstart", "-k", "gui/\(getuid())/\(l)"]
        try? p.run(); p.waitUntilExit()
        log.write("restart_run", ["label": l, "exit": "\(p.terminationStatus)", "hash": String(a.hash.prefix(12))])
    }
}

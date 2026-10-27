import Foundation

/// App Mesh (Kingdom t1087u): which apps exist, their ports, agents, MCP connections, models and skills, read from the
/// hub (~/m3ta-os/hub/agents/APP-MAP.md + INDEX files). Read-only: fixes/restarts are only ever queued for approval.
public struct AppMeshEntry: Sendable, Equatable, Identifiable {
    public let app: String
    public let ports: [Int]
    public let portNote: String
    public let agents: [String]
    public let mcp: [String]
    public var skills: [String] = []
    public var model: String?
    public var id: String { app }
    public var slug: String { AppMesh.slug(app) }
    public var pending: Bool { ports.isEmpty && (portNote.lowercased().contains("not found") || portNote.lowercased().contains("pending")) }
    public init(app: String, ports: [Int], portNote: String, agents: [String], mcp: [String], skills: [String] = [], model: String? = nil) {
        self.app = app; self.ports = ports; self.portNote = portNote; self.agents = agents; self.mcp = mcp; self.skills = skills; self.model = model
    }
}

public enum AppHealth: Sendable, Equatable { case up, down, partial, unknown, pending
    public var label: String { switch self { case .up: "Up"; case .down: "Down"; case .partial: "Partial"; case .unknown: "Unknown"; case .pending: "Pending" } } }

public enum AppMesh {
    /// Apps Kingdom wants shown even if APP-MAP.md is missing or doesn't list them yet.
    public static let expected: [(String, [Int])] = [("OpenBot", [3010]), ("OpenDots", [4310]), ("OpenMuse", [8091]), ("OpenDuet", []), ("CopilotKit runtime", [9782]),
                                                     ("Paperclip", []), ("Plane", []), ("Linear", []), ("AionUi", [])]
    public static func slug(_ s: String) -> String {
        let base = s.lowercased().components(separatedBy: CharacterSet(charactersIn: "(")).first ?? s
        return base.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " ", with: "-")
    }
    static func split(_ cell: String) -> [String] {
        cell.replacingOccurrences(of: "→", with: ",").components(separatedBy: CharacterSet(charactersIn: ",;"))
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && $0 != "—" && $0 != "-" }
    }
    /// Ports: 4–5 digit numbers that are NOT inside a parenthetical about other (down) stack parts.
    static func ports(_ cell: String) -> [Int] {
        var main = cell
        if let r = main.range(of: "(") { main = String(main[..<r.lowerBound]) }
        let nums = main.matches(of: /\b(\d{4,5})\b/).compactMap { Int($0.1) }.filter { (1024...65535).contains($0) }
        return Array(NSOrderedSet(array: nums)) as? [Int] ?? nums
    }
    /// Defensive parse of the first markdown table that has App / Agents / MCP columns. Unknown rows are kept; bad rows skipped.
    public static func parse(_ md: String) -> (entries: [AppMeshEntry], model: String?) {
        var model: String?
        if let line = md.split(separator: "\n").first(where: { $0.lowercased().contains("default model") }), let m = line.firstMatch(of: /`([^`]+)`/) { model = String(m.1) }
        var cols: [String: Int]?; var out: [AppMeshEntry] = []
        for raw in md.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("|") else { if cols != nil && !out.isEmpty { break }; continue }
            let cells = line.split(separator: "|", omittingEmptySubsequences: false).dropFirst().dropLast().map { $0.trimmingCharacters(in: .whitespaces) }
            if cols == nil {
                let h = cells.map { $0.lowercased() }
                if let a = h.firstIndex(where: { $0 == "app" || $0 == "apps" }) {
                    cols = ["app": a]; cols?["port"] = h.firstIndex { $0.hasPrefix("port") }; cols?["agents"] = h.firstIndex { $0.hasPrefix("agent") }; cols?["mcp"] = h.firstIndex { $0.contains("mcp") }
                }
                continue
            }
            if cells.allSatisfy({ $0.allSatisfy { "-: ".contains($0) } }) { continue }
            guard let c = cols, let ai = c["app"], ai < cells.count, !cells[ai].isEmpty else { continue }
            func cell(_ k: String) -> String { c[k].flatMap { $0 < cells.count ? cells[$0] : nil } ?? "" }
            out.append(AppMeshEntry(app: cells[ai], ports: ports(cell("port")), portNote: cell("port"), agents: split(cell("agents")), mcp: split(cell("mcp")), model: model))
        }
        return (out, model)
    }
    /// Merge parsed entries with the expected list; anything missing shows as pending.
    public static func merged(_ parsed: [AppMeshEntry], model: String?) -> [AppMeshEntry] {
        var out = parsed
        for (name, ports) in expected where !parsed.contains(where: { slug($0.app).hasPrefix(slug(name).prefix(5)) || slug(name).hasPrefix(slug($0.app).prefix(5)) }) {
            out.append(AppMeshEntry(app: name, ports: ports, portNote: "pending — not in APP-MAP.md yet", agents: [], mcp: [], model: model))
        }
        return out
    }
    /// Skills mapped to an app: INDEX lines (bullets or table rows) that mention the app or one of its agents.
    public static func skills(for e: AppMeshEntry, index: String, limit: Int = 12) -> [String] {
        let keys = ([e.app.components(separatedBy: " (").first ?? e.app] + e.agents).map { $0.lowercased() }.filter { $0.count >= 3 }
        return index.split(separator: "\n").compactMap { l -> String? in
            let s = l.lowercased(); guard keys.contains(where: { s.contains($0) }) else { return nil }
            if let m = l.firstMatch(of: /\[([^\]]+)\]/) { return String(m.1) }
            if let m = l.firstMatch(of: /`([^`]+)`/) { return String(m.1) }
            return nil
        }.filter { !$0.hasPrefix("~") && !$0.hasPrefix("/") && !$0.contains("/") }.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }.prefix(limit).map { $0 }
    }
    /// Stack services that belong to an app (by slug prefix), e.g. openduet → openduet, openduet-web, openduet-harness.
    public static func services(for e: AppMeshEntry, in stack: BamaStack?) -> [(String, BamaStack.Service)] {
        guard let s = stack else { return [] }
        let key = e.slug.hasPrefix("copilotkit") ? "cpk" : String(e.slug.split(separator: "-").first ?? "")
        return s.sorted.filter { $0.name.hasPrefix(key) }.map { ($0.name, $0.svc) }
    }
    public static func health(_ e: AppMeshEntry, services: [(String, BamaStack.Service)], probes: [Int: Bool]) -> AppHealth {
        if e.pending { return .pending }
        let ups = services.map { $0.1.status == "up" } + e.ports.compactMap { probes[$0] }
        if ups.isEmpty { return e.portNote.hasPrefix("pending") ? .pending : .unknown }
        return ups.allSatisfy { $0 } ? .up : (ups.contains(true) ? .partial : .down)
    }
    /// Loopback-only GET probe (any HTTP response = listening).
    public static func probe(_ port: Int, timeout: TimeInterval = 2) async -> Bool {
        guard (1024...65535).contains(port), let u = URL(string: "http://127.0.0.1:\(port)/") else { return false }
        var r = URLRequest(url: u, timeoutInterval: timeout); r.httpMethod = "GET"
        return (try? await URLSession.shared.data(for: r)).map { ($0.1 as? HTTPURLResponse) != nil } ?? false
    }
}

public extension ReaMcpClient {
    /// Queue a fix/restart for the coach. rea-mcp only accepts `supervisor.restart:<service>` here and, once approved,
    /// records it as a MANUAL step — nothing is restarted automatically. Returns the approval id.
    func queueRestart(_ service: String, transport t: (any McpTransport)? = nil) async throws -> String {
        guard service.wholeMatch(of: /[a-z0-9][a-z0-9-]{0,40}/) != nil, url.host == "127.0.0.1" else { throw ReaMcpError.notLoopback }
        var c = URLComponents(url: url, resolvingAgainstBaseURL: false)!; c.path = "/approvals/hold"
        let body = try JSONSerialization.data(withJSONObject: ["action": "supervisor.restart:\(service)", "args": ["from": "bama-app-mesh"]])
        let (d, code) = try await (t ?? transport).post(c.url!, body: body, headers: ["Content-Type": "application/json"])
        guard code == 200, let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let id = o["id"] as? String else { throw ReaMcpError.http(code) }
        return id
    }
}

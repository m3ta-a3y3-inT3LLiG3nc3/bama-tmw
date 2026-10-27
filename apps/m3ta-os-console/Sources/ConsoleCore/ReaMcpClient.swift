import Foundation

/// Minimal MCP JSON-RPC 2.0 client over streamable HTTP (single POST; accepts JSON or one SSE `data:` frame).
/// Mac only: loopback 127.0.0.1:9783/mcp. iOS/watchOS must use a TailnetEndpoint (https *.ts.net) — not enabled yet.
/// Read tools run directly. Any tool not in `readTools` is refused client-side: writes go through rea-mcp's
/// approval flow (they come back `awaiting_approval`) and are decided only by the coach in the Approvals inbox.
public protocol McpTransport: Sendable { func post(_ url: URL, body: Data, headers: [String: String]) async throws -> (Data, Int) }

public struct URLSessionTransport: McpTransport {
    public init() {}
    public func post(_ url: URL, body: Data, headers: [String: String]) async throws -> (Data, Int) {
        var q = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        q.httpMethod = "POST"; q.httpBody = body
        headers.forEach { q.setValue($1, forHTTPHeaderField: $0) }
        let (d, r) = try await JarvisClient.session(10).data(for: q)
        return (d, (r as? HTTPURLResponse)?.statusCode ?? 0)
    }
}

public enum ReaMcpError: Error, Equatable, LocalizedError {
    case http(Int), rpc(String), badResponse, notReadOnly(String), notLoopback
    public var errorDescription: String? {
        switch self {
        case .http(let c): "rea-mcp HTTP \(c)"
        case .rpc(let m): "rea-mcp error: \(m)"
        case .badResponse: "unexpected rea-mcp response"
        case .notReadOnly(let t): "\(t) can change things — it must go through the approval flow"
        case .notLoopback: "rea-mcp must be reached over loopback on the Mac"
        }
    }
}

public struct McpTool: Decodable, Sendable, Equatable { public let name: String; public let description: String? }

public final class ReaMcpClient: Sendable {
    public let url: URL
    let transport: any McpTransport
    /// Tools the console may call directly. Everything else is refused (writes need JEV approval).
    public static let readTools: Set<String> = ["rea_orbit_status", "rea_orbit_projects", "rea_orbit_agents", "rea_orbit_tasks", "rea_orbit_roster",
        "rea_orbit_trackers", "rea_orbit_stats", "rea_skills_list", "rea_skills_search", "rea_skills_get", "rea_brains_status", "rea_brains_search",
        "rea_approvals_list", "rea_ledger_tail", "rea_hyperagent_status", "rea_clianything_status", "rea_phonefarm_status"]
    public init(url: URL, transport: any McpTransport = URLSessionTransport()) throws {
        guard Self.allowed(url) else { throw ReaMcpError.notLoopback }
        self.url = url; self.transport = transport
    }
    public static func mac(port: Int = JarvisEndpoint.fromDefaults().reaPort, transport: any McpTransport = URLSessionTransport()) -> ReaMcpClient {
        try! ReaMcpClient(url: URL(string: "http://127.0.0.1:\(port)/mcp")!, transport: transport)
    }
    /// http only to 127.0.0.1; otherwise https to a *.ts.net MagicDNS name.
    public static func allowed(_ u: URL) -> Bool {
        guard let h = u.host?.lowercased() else { return false }
        if u.scheme == "http" { return h == "127.0.0.1" }
        return u.scheme == "https" && TailnetEndpoint.isTailnetHost(h)
    }

    /// Extract the JSON-RPC object from a JSON body or an SSE body.
    public static func unwrap(_ d: Data) throws -> [String: Any] {
        var data = d
        if let s = String(data: d, encoding: .utf8), !s.trimmingCharacters(in: .whitespaces).hasPrefix("{"),
           let line = s.split(separator: "\n").first(where: { $0.hasPrefix("data:") }) {
            data = Data(line.dropFirst(5).trimmingCharacters(in: .whitespaces).utf8)
        }
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ReaMcpError.badResponse }
        if let e = o["error"] as? [String: Any] { throw ReaMcpError.rpc(e["message"] as? String ?? "unknown") }
        guard let r = o["result"] as? [String: Any] else { throw ReaMcpError.badResponse }
        return r
    }
    func rpc(_ method: String, _ params: [String: Any]) async throws -> [String: Any] {
        let body = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": Int.random(in: 1...1_000_000), "method": method, "params": params])
        let (d, code) = try await transport.post(url, body: body, headers: ["Content-Type": "application/json", "Accept": "application/json, text/event-stream"])
        guard code == 200 else { throw ReaMcpError.http(code) }
        return try Self.unwrap(d)
    }
    public func listTools() async throws -> [McpTool] {
        let r = try await rpc("tools/list", [:])
        let d = try JSONSerialization.data(withJSONObject: r["tools"] ?? [])
        return try JSONDecoder().decode([McpTool].self, from: d)
    }
    /// Call a read tool; returns rea's envelope (`structuredContent`, or parsed first text block).
    public func callRead(_ name: String, _ args: [String: Any] = [:]) async throws -> [String: Any] {
        guard Self.readTools.contains(name) else { throw ReaMcpError.notReadOnly(name) }
        let r = try await rpc("tools/call", ["name": name, "arguments": args])
        if let s = r["structuredContent"] as? [String: Any] { return s }
        if let c = r["content"] as? [[String: Any]], let t = c.first?["text"] as? String,
           let o = try? JSONSerialization.jsonObject(with: Data(t.utf8)) as? [String: Any] { return o }
        throw ReaMcpError.badResponse
    }
    public func callReadData(_ name: String, _ args: [String: Any] = [:]) async throws -> Data {
        try JSONSerialization.data(withJSONObject: try await callRead(name, args)["output"] ?? [:])
    }
}

// MARK: typed reads
public struct ReaApproval: Codable, Sendable, Equatable, Identifiable { public let id: String, action: String, status: String; public let createdAt: String? }
public struct ReaSkill: Codable, Sendable, Equatable, Identifiable { public let id: String, name: String, description: String, source: String; public let writes: Bool? }

public extension ReaMcpClient {
    func approvals(status: String? = "pending") async throws -> [ReaApproval] {
        struct W: Decodable { let approvals: [ReaApproval] }
        return try JSONDecoder().decode(W.self, from: await callReadData("rea_approvals_list", status.map { ["status": $0] } ?? [:])).approvals
    }
    func searchSkills(_ q: String, limit: Int = 30) async throws -> [ReaSkill] {
        struct W: Decodable { let results: [ReaSkill] }
        return try JSONDecoder().decode(W.self, from: await callReadData("rea_skills_search", ["q": q, "limit": limit])).results
    }
}

/// Approvals inbox backed by rea-mcp: list via `rea_approvals_list` (MCP), decide via the existing gated sidecar
/// route `POST /api/approvals/<id>/<approve|deny>` on 9782. ApprovalInbox guarantees once-only + owner auth.
public struct ReaApprovalsAPI: ApprovalsAPI {
    let rea: ReaMcpClient, runtime: URL, transport: any McpTransport
    public init(rea: ReaMcpClient, runtimeBase: URL = JarvisEndpoint.fromDefaults().runtime(""), transport: any McpTransport = URLSessionTransport()) {
        self.rea = rea; self.runtime = runtimeBase; self.transport = transport
    }
    public func pending() async throws -> [PendingApproval] {
        let fmt = ISO8601DateFormatter(); fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return try await rea.approvals(status: "pending").filter { $0.status == "pending" }.map {
            let t = $0.createdAt.flatMap { fmt.date(from: $0) ?? ISO8601DateFormatter().date(from: $0) }?.timeIntervalSince1970 ?? 0
            let kind = $0.action.split(separator: ".").first.map(String.init) ?? "action"
            return PendingApproval(id: $0.id, tool: $0.action, kind: kind, summary: $0.action, at: Int(t))
        }.sorted { $0.at > $1.at }
    }
    public func decide(_ id: String, _ d: ApprovalDecision) async throws {
        guard id.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }) else { throw ReaMcpError.badResponse }
        let u = runtime.appendingPathComponent("api/approvals/\(id)/\(d.rawValue)")
        let (_, code) = try await transport.post(u, body: Data(#"{"reason":"coach (BAMA console)"}"#.utf8), headers: ["Content-Type": "application/json"])
        guard code == 200 else { throw ReaMcpError.http(code) }
    }
}

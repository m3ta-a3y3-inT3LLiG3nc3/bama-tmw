import Foundation

/// JARVIS HUD features ported natively (shared by Mac and, later, iPad/iPhone via tailnet).

/// GET /api/bama/stack on 9782 — services only (config is shown as labels, never values of secrets).
public struct BamaStack: Decodable, Sendable, Equatable {
    public struct Service: Decodable, Sendable, Equatable { public let status: String; public let code: Int?; public let ms: Int?; public let action: String? }
    public let services: [String: Service]
    public var sorted: [(name: String, svc: Service)] { services.sorted { $0.key < $1.key }.map { ($0.key, $0.value) } }
    public var upCount: Int { services.values.filter { $0.status == "up" }.count }
}

/// "/orbit agents", "/skills <q>", "/skills get <id>", "/brains <q>", "/brains status" → a READ tool call.
/// Mirrors jarvis-hud parseM3taCommand. Write ops (/orbit message|upsert_row|result, /skills run) are refused here:
/// they must be queued through rea-mcp's approval flow, never run from chat.
public enum ConsoleCommand: Equatable, Sendable {
    case read(tool: String, args: [String: String])
    case needsApproval(String)
    case chat(String)

    public static let orbitReads = ["status", "projects", "agents", "tasks", "roster", "trackers", "stats"]
    public static let orbitWrites = ["upsert_row", "message", "result", "heartbeat"]

    public static func parse(_ raw: String) -> ConsoleCommand {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = t.split(separator: " ", maxSplits: 2).map(String.init)
        guard let head = parts.first, head.hasPrefix("/") else { return .chat(t) }
        let rest = parts.dropFirst().joined(separator: " ").trimmingCharacters(in: .whitespaces)
        switch head {
        case "/orbit":
            let op = (parts.count > 1 ? parts[1] : "status").replacingOccurrences(of: "-", with: "_")
            if orbitReads.contains(op) { return .read(tool: "rea_orbit_\(op)", args: [:]) }
            if orbitWrites.contains(op) { return .needsApproval("/orbit \(op) changes Orbit — queue it from JARVIS so it lands in Approvals") }
            return .chat(t)
        case "/skills":
            if parts.count > 1, parts[1] == "get" { return .read(tool: "rea_skills_get", args: ["id": parts.count > 2 ? parts[2] : ""]) }
            if parts.count > 1, parts[1] == "run" { return .needsApproval("/skills run executes a skill — it needs JEV approval") }
            if rest.isEmpty || parts[1] == "list" { return .read(tool: "rea_skills_list", args: [:]) }
            return .read(tool: "rea_skills_search", args: ["q": rest])
        case "/brains":
            if rest.isEmpty || rest == "status" { return .read(tool: "rea_brains_status", args: [:]) }
            return .read(tool: "rea_brains_search", args: ["q": rest])
        default: return .chat(t)
        }
    }
}

/// Read-only parse of ~/m3ta-os/hub/skills/INDEX.md (markdown list/table lines) as an offline skills fallback.
public enum HubSkillIndex {
    public static let path = NSString(string: "~/m3ta-os/hub/skills/INDEX.md").expandingTildeInPath
    public static func parse(_ md: String) -> [String] {
        md.split(separator: "\n").compactMap { l in
            let s = l.trimmingCharacters(in: .whitespaces)
            guard s.hasPrefix("- ") || (s.hasPrefix("|") && !s.contains("---")) else { return nil }
            let v = s.trimmingCharacters(in: CharacterSet(charactersIn: "-| ")).replacingOccurrences(of: "`", with: "")
            return v.isEmpty ? nil : v
        }
    }
    public static func search(_ q: String, in lines: [String]) -> [String] {
        let k = q.lowercased(); return k.isEmpty ? lines : lines.filter { $0.lowercased().contains(k) }
    }
}

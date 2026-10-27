import Foundation

/// Canonical OpenBot ↔ Orbit ↔ Grok Bot map (~/m3ta-os/mesh-map/bot-map-YYYYMMDD.json). Read-only.
public struct BotMap: Decodable, Sendable {
    public struct Counts: Decodable, Sendable {
        public let openbot_bots: Int, orbit_agents: Int, grokbot_agents: Int, mapped_to_orbit: Int, mapped_to_grokbot: Int, brain_wired: Int
    }
    public struct OpenBot: Decodable, Sendable { public let id: String, name: String, provider: String?, model: String?, skills_count: Int?, description_head: String?, preview: String? }
    public struct OrbitRef: Decodable, Sendable, Hashable { public let id: String, name: String, external_id: String?, status: String?, type: String? }
    public struct GrokRef: Decodable, Sendable { public let id: String, name: String }
    public struct Brain: Decodable, Sendable { public let wired: Bool?, evidence: String? }
    public struct Bot: Decodable, Sendable, Identifiable {
        public let openbot: OpenBot, role: String, orbit: [OrbitRef], grokbot: GrokRef?, brain: Brain?, status: String, flags: [String]
        public var id: String { openbot.id }
        /// Tri-state: nil when the map doesn't say. Never guessed.
        public var brainWired: Bool? { brain?.wired }
    }
    public let generated: String
    public let counts: Counts
    public let conflicts: [String]
    public let bots: [Bot]
}

public enum BotFilter: String, CaseIterable, Sendable, Identifiable {
    case all = "All", bridges = "Bridges", gaps = "Gaps", conflicts = "Conflicts", noBrain = "Not on brain"
    public var id: String { rawValue }
    public func matches(_ b: BotMap.Bot) -> Bool {
        switch self {
        case .all: true
        case .bridges: b.status == "bridge"
        case .gaps: b.orbit.isEmpty || b.grokbot == nil
        case .conflicts: b.flags.contains { $0.hasPrefix("conflict") || $0 == "duplicate-name" || $0 == "multiple-orbit-records" }
        case .noBrain: b.brainWired != true
        }
    }
}

public extension BotMap {
    func filtered(query: String, filter: BotFilter) -> [Bot] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return bots.filter { b in
            guard filter.matches(b) else { return false }
            if q.isEmpty { return true }
            let hay = ([b.openbot.name, b.role, b.openbot.model ?? "", b.grokbot?.name ?? ""] + b.orbit.map(\.name) + b.flags).joined(separator: " ").lowercased()
            return hay.contains(q)
        }
    }
}

public enum BotMapLoader {
    public static let bundledName = "bot-map-20261027"
    public static func decode(_ d: Data) throws -> BotMap { try JSONDecoder().decode(BotMap.self, from: d) }
    public static func load(from url: URL) throws -> BotMap { try decode(Data(contentsOf: url)) }
    public static func loadBundled() throws -> BotMap {
        guard let u = Bundle.module.url(forResource: bundledName, withExtension: "json") else { throw CocoaError(.fileNoSuchFile) }
        return try load(from: u)
    }
}

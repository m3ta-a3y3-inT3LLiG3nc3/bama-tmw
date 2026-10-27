import Foundation
import Observation

/// M3 · JEV gate: reads ~/.config/m3ta/jev/rules/*.json (read-only) and decides whether an action
/// may run, needs Touch ID, or is blocked. The console never writes rules.
public struct JevRule: Sendable, Equatable {
    public let name: String
    public let dailyUSDCap: Double
    public init(name: String, dailyUSDCap: Double) { self.name = name; self.dailyUSDCap = dailyUSDCap }
}

public enum JevVerdict: Sendable, Equatable {
    case allow            // $0 / local
    case needsOwner       // paid but within cap → Touch ID
    case blocked(String)  // over cap or unknown rule
}

public enum JevGate {
    public static var rulesDir: URL {
        #if os(macOS)
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".config/m3ta/jev/rules")
        #else
        URL.applicationSupportDirectory.appending(path: "jev/rules") // devices never read the Mac's rules; empty → paid actions blocked
        #endif
    }
    public static func loadRules(from dir: URL = rulesDir) -> [JevRule] {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }.compactMap { u in
            guard let d = try? Data(contentsOf: u), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
            return JevRule(name: u.deletingPathExtension().lastPathComponent, dailyUSDCap: (o["daily_usd_cap"] as? NSNumber)?.doubleValue ?? 0)
        }.sorted { $0.name < $1.name }
    }
    public static func verdict(costUSD: Double, rule: JevRule?, spentToday: Double = 0) -> JevVerdict {
        if costUSD <= 0 { return .allow }
        guard let r = rule else { return .blocked("No JEV rule for this provider") }
        if spentToday + costUSD > r.dailyUSDCap { return .blocked(String(format: "Over %@ daily cap ($%.2f)", r.name, r.dailyUSDCap)) }
        return .needsOwner
    }
}

public struct GatedAction: Identifiable, Sendable {
    public let id: UUID
    public let title: String, detail: String, provider: String?
    public let costUSD: Double
    public let run: @Sendable () async -> Void
    public init(id: UUID = UUID(), title: String, detail: String, provider: String? = nil, costUSD: Double = 0, run: @escaping @Sendable () async -> Void) {
        self.id = id; self.title = title; self.detail = detail; self.provider = provider; self.costUSD = costUSD; self.run = run
    }
}

public enum ApprovalOutcome: String, Sendable, Equatable { case approved, denied, blocked, authFailed }

/// Owner authentication seam (Touch ID in the app, stub in tests).
public protocol OwnerAuthenticator: Sendable { func authenticate(reason: String) async -> Bool }

/// Approval inbox. Invariants (tested): approve runs the action exactly once; deny never runs it;
/// a decided item can never be decided again; paid actions require owner auth first.
@MainActor @Observable public final class ApprovalGate {
    public private(set) var pending: [GatedAction] = []
    public private(set) var history: [(id: UUID, title: String, outcome: ApprovalOutcome, at: Date)] = []
    public var rules: [JevRule]
    private var decided: Set<UUID> = []
    private let auth: OwnerAuthenticator
    public init(auth: OwnerAuthenticator, rules: [JevRule] = JevGate.loadRules()) { self.auth = auth; self.rules = rules }

    public func enqueue(_ a: GatedAction) { guard !decided.contains(a.id), !pending.contains(where: { $0.id == a.id }) else { return }; pending.append(a) }
    public func verdict(for a: GatedAction) -> JevVerdict { JevGate.verdict(costUSD: a.costUSD, rule: rules.first { $0.name == a.provider }) }

    @discardableResult public func approve(_ id: UUID) async -> ApprovalOutcome? {
        guard !decided.contains(id), let a = pending.first(where: { $0.id == id }) else { return nil }
        decided.insert(id) // claim before any await so a double-click can't run twice
        switch verdict(for: a) {
        case .blocked: return finish(a, .blocked)
        case .needsOwner:
            guard await auth.authenticate(reason: "Approve “\(a.title)”") else { decided.remove(id); record(a, .authFailed); return .authFailed }
            fallthrough
        case .allow:
            _ = finish(a, .approved); await a.run(); return .approved
        }
    }
    @discardableResult public func deny(_ id: UUID) -> ApprovalOutcome? {
        guard !decided.contains(id), let a = pending.first(where: { $0.id == id }) else { return nil }
        decided.insert(id); return finish(a, .denied)
    }
    private func finish(_ a: GatedAction, _ o: ApprovalOutcome) -> ApprovalOutcome { pending.removeAll { $0.id == a.id }; record(a, o); return o }
    private func record(_ a: GatedAction, _ o: ApprovalOutcome) { history.insert((a.id, a.title, o, .now), at: 0) }
}

/// M6 · embedded local apps (loopback only).
public struct EmbeddedApp: Identifiable, Sendable, Hashable {
    public let id: String, name: String, icon: String, appName: String, defaultPort: Int
    public static let all: [EmbeddedApp] = [
        .init(id: "openbot", name: "OpenBot", icon: "message.badge.waveform", appName: "OpenBot", defaultPort: 28417),
        .init(id: "opendots", name: "OpenDots", icon: "circle.grid.3x3", appName: "OpenDots", defaultPort: 4310),
        .init(id: "openmuse", name: "OpenMuse", icon: "music.note.list", appName: "OpenMuse", defaultPort: 8797),
        .init(id: "openduet", name: "OpenDuet", icon: "person.2.wave.2", appName: "openbot-desktop", defaultPort: 53363),
        .init(id: "aimock", name: "aimock", icon: "testtube.2", appName: "aimock", defaultPort: 4010),
    ]
    public func url(port: Int) -> URL { URL(string: "http://127.0.0.1:\(port)/")! }
    public static func isLoopback(_ u: URL) -> Bool { ["127.0.0.1", "localhost", "::1"].contains(u.host() ?? "") }
}

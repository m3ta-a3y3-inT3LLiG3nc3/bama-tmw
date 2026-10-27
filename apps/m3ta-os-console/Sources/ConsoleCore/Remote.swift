import Foundation
import Observation

/// Where a client reaches the JARVIS sidecar.
/// - Mac: loopback only (127.0.0.1:9782 / :9783). Unchanged.
/// - iPhone / iPad / Watch: the Mac's Tailscale MagicDNS name over HTTPS (`*.ts.net`), which only works once
///   Kingdom has OK'd `tailscale serve` on the Mac. The sidecar itself stays bound to 127.0.0.1; nothing is
///   exposed publicly, no 0.0.0.0, no Funnel. No secrets are stored here — identity comes from the tailnet.
public protocol SidecarURLs: Sendable {
    func runtime(_ path: String) -> URL
    func rea(_ path: String) -> URL
}
extension JarvisEndpoint: SidecarURLs {}

public struct TailnetEndpoint: SidecarURLs, Equatable {
    public let host: String
    /// `tailscale serve` path prefixes that proxy to the loopback ports (see apps/m3ta-os-apple/TAILNET.md).
    public static let runtimePrefix = "/jarvis", reaPrefix = "/rea"
    public init?(host raw: String) {
        let h = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard Self.isTailnetHost(h) else { return nil }
        host = h
    }
    /// Only MagicDNS names under ts.net. Rejects IPs (incl. 0.0.0.0), public hosts, ports, schemes, paths.
    public static func isTailnetHost(_ h: String) -> Bool {
        guard h.hasSuffix(".ts.net"), h.count > 7, h.count < 254 else { return false }
        let labels = h.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 3 else { return false }
        return labels.allSatisfy { l in !l.isEmpty && l.count <= 63 && l.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" } && l.first != "-" && l.last != "-" }
    }
    public func runtime(_ path: String) -> URL { URL(string: "https://\(host)\(Self.runtimePrefix)\(path)")! }
    public func rea(_ path: String) -> URL { URL(string: "https://\(host)\(Self.reaPrefix)\(path)")! }
    public static let defaultsKey = "tailnetMacHost"
    public static func fromDefaults(_ d: UserDefaults = .standard) -> TailnetEndpoint? { d.string(forKey: defaultsKey).flatMap { TailnetEndpoint(host: $0) } }
}

public extension JarvisClient {
    static func status(at e: some SidecarURLs) async -> JarvisStatus {
        async let r = get(e.runtime("/health"), as: RuntimeHealth.self)
        async let m = get(e.rea("/health"), as: ReaHealth.self)
        async let mo = get(e.runtime("/api/models"), as: ModelRoute.self)
        async let s = get(e.runtime("/api/rea/skills"), as: ReaSkills.self)
        return JarvisStatus(runtime: await r, rea: await m, models: await mo, skills: await s, checkedAt: Date())
    }
}

/// Glanceable health summary shared by iPhone dashboard, Watch glance and widgets.
public struct HealthGlance: Sendable, Equatable, Codable {
    public enum Level: String, Sendable, Codable { case good, degraded, offline, unknown }
    public let level: Level, title: String, detail: String, pendingApprovals: Int, at: Date
    public init(level: Level, title: String, detail: String, pendingApprovals: Int, at: Date) {
        self.level = level; self.title = title; self.detail = detail; self.pendingApprovals = pendingApprovals; self.at = at
    }
    public static func from(_ s: JarvisStatus?, pending: Int) -> HealthGlance {
        guard let s else { return .init(level: .unknown, title: "Not paired", detail: "Add your Mac's tailnet name", pendingApprovals: pending, at: .now) }
        let level: Level = s.runtimeUp && s.reaUp ? .good : (s.fullyOffline ? .offline : .degraded)
        let title = switch level { case .good: "All systems go"; case .degraded: "Partly up"; case .offline: "Mac offline"; case .unknown: "Unknown" }
        let detail = "Runtime \(s.runtimeUp ? "up" : "down") · Tools \(s.reaUp ? "up" : "down")" + (s.skills.value.map { " · \($0.tools.count) skills" } ?? "")
        return .init(level: level, title: title, detail: detail, pendingApprovals: pending, at: s.checkedAt)
    }
    public static let placeholder = HealthGlance(level: .good, title: "All systems go", detail: "Runtime up · Tools up", pendingApprovals: 2, at: .now)
}

/// A JEV pending request as written by the gate (`~/.config/m3ta/jev/pending/<id>.json`: tool, kind, summary, at).
public struct PendingApproval: Codable, Sendable, Equatable, Identifiable, Hashable {
    public let id: String, tool: String, kind: String, summary: String, at: Int
    public init(id: String, tool: String, kind: String, summary: String, at: Int) { self.id = id; self.tool = tool; self.kind = kind; self.summary = summary; self.at = at }
    public var date: Date { Date(timeIntervalSince1970: TimeInterval(at > 10_000_000_000 ? at / 1000 : at)) }
}

public enum ApprovalDecision: String, Codable, Sendable { case approve, deny }

/// Remote approvals contract. PROPOSED sidecar routes (not served by 9782 yet — adding them needs Kingdom's OK + a 9782 restart):
///   GET  /api/jev/pending            → {"pending":[{id,tool,kind,summary,at}]}
///   POST /api/jev/decide {id,decision} → {"ok":true}   (sidecar re-checks the JEV gate; device is never trusted for cost)
public protocol ApprovalsAPI: Sendable {
    func pending() async throws -> [PendingApproval]
    func decide(_ id: String, _ d: ApprovalDecision) async throws
}

public struct HTTPApprovalsAPI: ApprovalsAPI {
    public let base: any SidecarURLs
    public init(base: any SidecarURLs) { self.base = base }
    struct List: Decodable { let pending: [PendingApproval] }
    public static func parse(_ d: Data) throws -> [PendingApproval] { try JSONDecoder().decode(List.self, from: d).pending.sorted { $0.at > $1.at } }
    public func pending() async throws -> [PendingApproval] {
        let (d, r) = try await JarvisClient.session(4).data(from: base.runtime("/api/jev/pending"))
        guard (r as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try Self.parse(d)
    }
    public func decide(_ id: String, _ dec: ApprovalDecision) async throws {
        var q = URLRequest(url: base.runtime("/api/jev/decide")); q.httpMethod = "POST"
        q.setValue("application/json", forHTTPHeaderField: "Content-Type")
        q.httpBody = try JSONEncoder().encode(["id": id, "decision": dec.rawValue])
        let (_, r) = try await JarvisClient.session(6).data(for: q)
        guard (r as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
    }
}

/// Demo data for simulators / previews / screenshots. Never used when a tailnet host is set.
public struct DemoApprovalsAPI: ApprovalsAPI {
    public init() {}
    public static let items = [
        PendingApproval(id: "jev_demo_restart", tool: "jarvis.restart", kind: "service", summary: "Restart OpenDuet agent (53363)", at: 1_793_120_000),
        PendingApproval(id: "jev_demo_nexos", tool: "nexos.chat", kind: "paid", summary: "Opus 5.5 call via nexos (est. $0.04)", at: 1_793_119_000),
    ]
    public func pending() async throws -> [PendingApproval] { Self.items }
    public func decide(_ id: String, _ d: ApprovalDecision) async throws {}
}

/// Device approval inbox. Invariants (tested): each id is decided at most once; deny never needs owner auth;
/// approve needs owner auth (Face ID / wrist) first; a failed auth leaves the item pending.
@MainActor @Observable public final class ApprovalInbox {
    public private(set) var items: [PendingApproval] = []
    public private(set) var lastError: String?
    public private(set) var decided: [String: ApprovalDecision] = [:]
    let api: any ApprovalsAPI, auth: any OwnerAuthenticator
    public init(api: any ApprovalsAPI, auth: any OwnerAuthenticator) { self.api = api; self.auth = auth }
    public func refresh() async {
        do { items = try await api.pending().filter { decided[$0.id] == nil }; lastError = nil }
        catch { lastError = "Approvals unavailable (\(error.localizedDescription))" }
    }
    @discardableResult public func decide(_ id: String, _ d: ApprovalDecision) async -> Bool {
        guard decided[id] == nil, let item = items.first(where: { $0.id == id }) else { return false }
        decided[id] = d // claim before await
        if d == .approve, !(await auth.authenticate(reason: "Approve “\(item.summary)”")) { decided[id] = nil; lastError = "Not approved — authentication failed"; return false }
        do { try await api.decide(id, d); items.removeAll { $0.id == id }; return true }
        catch { decided[id] = nil; lastError = "Couldn't send decision"; return false }
    }
}

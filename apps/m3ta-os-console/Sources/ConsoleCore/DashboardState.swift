import Foundation

/// Snapshot contract for the M3ta Way dashboard (spec:
/// docs/designs/m3ta-way-dashboard-2026-11-02.md, data contract, plus
/// the ticker and social contracts and tab fields from the features
/// addendum, docs/designs/m3ta-way-dashboard-features-addendum-2026-11-02.md).
///
/// One Codable type, loaded the way `MeshState` loads: a bundled fixture
/// plus a Settings path override (`dashboardStatePath`). All fields are
/// optional except `capturedAt` and `source`, so a partial snapshot
/// renders what it has and omits the rest. Dates are ISO-8601 strings.
/// No number renders unless it traces to a named source; unknown stays
/// "Unknown", never zero.
public struct DashboardState: Codable, Sendable, Equatable {
    public let capturedAt: String            // required, ISO-8601
    public let source: String                // required
    public let briefLines: [BriefLine]?      // Panel 1
    public let surfaces: [SurfaceRow]?       // Panel 4
    public let revenue: RevenueState?        // Panel 5
    public let skillsBrain: SkillsBrainState? // Panel 6 block 2
    public let knowledge: KnowledgeState?    // Panel 7
    public let tickerItems: [TickerItem]?    // Features addendum, hero ticker
    public let social: SocialState?          // Features addendum, social panel
    public let appRows: [SurfaceRow]?        // Features addendum section 4 rows (Panel 4 + Meta OS tab)
    public let commsRows: [SurfaceRow]?      // Hermes tab
    public let platformModules: [SurfaceRow]? // Meta OS tab module grid
    public let intelligenceProjects: [SurfaceRow]? // Meta OS tab
    public let platformRows: [SurfaceRow]?   // Meta OS tab (EGM step, stack rows)
    public let workforceCensus: [SurfaceRow]? // A.D.A.M. tab

    public init(capturedAt: String, source: String,
                briefLines: [BriefLine]? = nil, surfaces: [SurfaceRow]? = nil,
                revenue: RevenueState? = nil, skillsBrain: SkillsBrainState? = nil,
                knowledge: KnowledgeState? = nil, tickerItems: [TickerItem]? = nil,
                social: SocialState? = nil, appRows: [SurfaceRow]? = nil,
                commsRows: [SurfaceRow]? = nil, platformModules: [SurfaceRow]? = nil,
                intelligenceProjects: [SurfaceRow]? = nil, platformRows: [SurfaceRow]? = nil,
                workforceCensus: [SurfaceRow]? = nil) {
        self.capturedAt = capturedAt; self.source = source
        self.briefLines = briefLines; self.surfaces = surfaces
        self.revenue = revenue; self.skillsBrain = skillsBrain
        self.knowledge = knowledge; self.tickerItems = tickerItems
        self.social = social; self.appRows = appRows
        self.commsRows = commsRows; self.platformModules = platformModules
        self.intelligenceProjects = intelligenceProjects; self.platformRows = platformRows
        self.workforceCensus = workforceCensus
    }
}

public struct BriefLine: Codable, Sendable, Equatable {
    public let kind: Kind                    // required; closed enum, unlike surface state words
    public let text: String                  // required
    public let sourceTag: String             // required
    public enum Kind: String, Codable, Sendable {
        case approval, calendar, blocked, knowledge, revenue
        /// Fixed brief ranking order (Panel 1): approval, calendar,
        /// blocked, knowledge, revenue.
        public var rank: Int {
            switch self {
            case .approval: return 0
            case .calendar: return 1
            case .blocked: return 2
            case .knowledge: return 3
            case .revenue: return 4
            }
        }
    }
    public init(kind: Kind, text: String, sourceTag: String) {
        self.kind = kind; self.text = text; self.sourceTag = sourceTag
    }
}

public struct SurfaceRow: Codable, Sendable, Equatable {
    public let name: String                  // required
    public let stateWord: String             // required; rendered raw if outside the vocabulary
    public let note: String?                 // free text, rendered as given
    public let asOf: String?                 // ISO-8601
    public let count: Int?                   // counts live here, never in note
    public let countAsOf: String?            // ISO-8601, required if count is present
    public let routeURL: String?             // external link target; absent means no link
    public init(name: String, stateWord: String, note: String? = nil, asOf: String? = nil,
                count: Int? = nil, countAsOf: String? = nil, routeURL: String? = nil) {
        self.name = name; self.stateWord = stateWord; self.note = note; self.asOf = asOf
        self.count = count; self.countAsOf = countAsOf; self.routeURL = routeURL
    }
    public var status: DashboardStatus { DashboardStatus(word: stateWord) }
    /// Stale = the row's own date (asOf, else countAsOf) is older than 24h.
    public func isStale(now: Date = Date()) -> Bool {
        guard let s = asOf ?? countAsOf, let d = SnapshotAge.date(s) else { return false }
        return now.timeIntervalSince(d) > 24 * 3600
    }
}

public struct RevenueState: Codable, Sendable, Equatable {
    public let ladder: [LadderRow]           // required if revenue is present
    public let verifiedRevenueLine: String?  // e.g. "$0"
    public let verifiedRevenueAsOf: String?  // required if the line is present
    public let gateNote: String?             // gate states in words
}
public struct LadderRow: Codable, Sendable, Equatable {
    public let name: String                  // required
    public let price: String                 // required; a string, never a number the app formats into a claim
    public let gateNote: String?
}

public struct SkillsBrainState: Codable, Sendable, Equatable {
    public let blockerLine: String           // required
    public let asOf: String                  // required, ISO-8601
}

public struct KnowledgeState: Codable, Sendable, Equatable {
    public let corpus: [CorpusItem]          // required if knowledge is present
    public let queueCounts: QueueCounts?
}
public struct CorpusItem: Codable, Sendable, Equatable {
    public let name: String                  // required
    public let stateWord: String             // required; same raw-render rule as surfaces
    public let note: String?
    public let asOf: String?
    public var status: DashboardStatus { DashboardStatus(word: stateWord) }
}
public struct QueueCounts: Codable, Sendable, Equatable {
    public let waiting: Int                  // required
    public let inPipeline: Int               // required
    public let failed: Int                   // required
    public let asOf: String                  // required, ISO-8601
}

/// Hero ticker item (features addendum section 2). The full item text,
/// number included, is rendered as written; the app never re-ranks or
/// rewrites ticker items.
public struct TickerItem: Codable, Sendable, Equatable {
    public let text: String                  // required; the full item as rendered
    public let sourceTag: String             // required; rendered after the item
    public let asOf: String                  // required, ISO-8601
    public init(text: String, sourceTag: String, asOf: String) {
        self.text = text; self.sourceTag = sourceTag; self.asOf = asOf
    }
}

/// Social panel contract (features addendum section 3). No metric value
/// exists until a producer reads one through a named connector route;
/// an absent `social` field renders the panel's designed state.
public struct SocialState: Codable, Sendable, Equatable {
    public let accounts: [SocialAccount]?
    public let activity: [SocialPost]?
}
public struct SocialAccount: Codable, Sendable, Equatable {
    public let platform: String              // required
    public let handle: String                // required
    public let followers: Int?               // followersAsOf required if present
    public let followersAsOf: String?
    public let windowLabel: String?          // e.g. "last 28d"
    public let metrics: [SocialMetric]?
}
public struct SocialMetric: Codable, Sendable, Equatable {
    public let name: String                  // the connector's own metric name
    public let value: String                 // string, never reformatted into a claim
    public let asOf: String                  // required, ISO-8601
}
public struct SocialPost: Codable, Sendable, Equatable {
    public let platform: String              // required
    public let stateWord: String             // published | scheduled | draft
    public let text: String                  // required; post text or its first line
    public let when: String                  // required, ISO-8601
    public let sourceTag: String             // required
}

public extension DashboardState {
    /// Panel 1 brief pipeline, deterministic code, never a model call:
    /// re-rank by kind in the fixed order, stable within a kind, omit
    /// absent kinds (no empty slots), cap after re-ranking.
    func rankedBriefLines(limit: Int = 5) -> [BriefLine] {
        guard let lines = briefLines else { return [] }
        let sorted = lines.enumerated().sorted { a, b in
            a.element.kind.rank != b.element.kind.rank
                ? a.element.kind.rank < b.element.kind.rank
                : a.offset < b.offset
        }.map(\.element)
        return Array(sorted.prefix(limit))
    }

    /// Stale = captured more than 24 hours ago (spec failure table: the
    /// age line turns to the warn tone and brief lines are prefixed).
    func isStale(now: Date = Date()) -> Bool {
        guard let d = SnapshotAge.date(capturedAt) else { return false }
        return now.timeIntervalSince(d) > 24 * 3600
    }

    /// Age line in the app's existing snapshot-age style.
    var ageDescription: String { SnapshotAge.describe(capturedAt) }

    /// Panel 4 ordering (deterministic, A5): blocked first, then stale
    /// snapshots, then the rest by status rank. Stable within a tier.
    func panel4OrderedSurfaces(now: Date = Date()) -> [SurfaceRow] {
        let rows = (surfaces ?? []) + (appRows ?? [])
        func tier(_ r: SurfaceRow) -> Int {
            if r.status == .blocked { return 0 }
            if r.status == .snapshot && r.isStale(now: now) { return 1 }
            return 2 + r.status.sortRank
        }
        return rows.enumerated().sorted { a, b in
            tier(a.element) != tier(b.element) ? tier(a.element) < tier(b.element) : a.offset < b.offset
        }.map(\.element)
    }
}

public enum DashboardStateLoader {
    public static var bundledFixtureURL: URL? {
        Bundle.module.url(forResource: "dashboard-state-2026-11-02", withExtension: "json")
    }
    public static func decode(_ data: Data) throws -> DashboardState {
        try JSONDecoder().decode(DashboardState.self, from: data)
    }
    public static func load(from url: URL) throws -> DashboardState {
        try decode(Data(contentsOf: url))
    }
    /// Throws when the fixture is missing. A set-but-unreadable override
    /// path must surface as an error in the store, never a silent
    /// fallback to this fixture (spec failure table).
    public static func loadBundled() throws -> DashboardState {
        guard let url = bundledFixtureURL else { throw CocoaError(.fileNoSuchFile) }
        return try load(from: url)
    }
}

/// The snapshot producer's shared composition step. The QB-side producer
/// job (existing check-in cadence) owns capture and file writing; this
/// pure function is the part both sides share: it folds the loopback
/// probe results, and only those, into a base snapshot. Every value it
/// writes traces to a probe field. A missing pending count composes as
/// "Unknown", never zero. No external collection happens here or in the
/// caller: the probe set is the spec's allowed loopback read set.
public enum DashboardSnapshotComposer {
    public static func compose(base: DashboardState, status: JarvisStatus,
                               capturedAt: String) -> DashboardState {
        let pending = status.rea.value?.pending
        let approvals = TickerItem(
            text: "Approvals pending: \(pending.map(String.init) ?? "Unknown")",
            sourceTag: "rea-mcp /health", asOf: capturedAt)
        // The live approvals segment leads the strip; the base items keep
        // their producer order after it, minus any older approvals item.
        let rest = (base.tickerItems ?? []).filter { !$0.text.hasPrefix("Approvals pending:") }
        let jarvis: SurfaceRow = {
            if status.runtimeUp, let m = status.models.value {
                return SurfaceRow(name: "JARVIS", stateWord: "live",
                    note: "Default route \(m.default.model) (\(m.default.paid ? "paid" : "local")) · paid models on: \(m.paidEnabledCount)",
                    asOf: capturedAt)
            }
            return SurfaceRow(name: "JARVIS", stateWord: "live",
                note: status.runtimeUp ? "Runtime healthy; model route unread" : "Runtime not answering at capture time",
                asOf: capturedAt)
        }()
        let surfaces = [jarvis] + (base.surfaces ?? []).filter { $0.name != "JARVIS" }
        return DashboardState(capturedAt: capturedAt, source: base.source,
            briefLines: base.briefLines, surfaces: surfaces,
            revenue: base.revenue, skillsBrain: base.skillsBrain,
            knowledge: base.knowledge, tickerItems: [approvals] + rest,
            social: base.social, appRows: base.appRows,
            commsRows: base.commsRows, platformModules: base.platformModules,
            intelligenceProjects: base.intelligenceProjects, platformRows: base.platformRows,
            workforceCensus: base.workforceCensus)
    }
}

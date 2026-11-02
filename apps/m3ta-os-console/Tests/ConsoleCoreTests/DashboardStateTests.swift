import Testing
import Foundation
@testable import ConsoleCore

/// Dashboard acceptance tests 1-5 from the spec (loader, ranking, age,
/// revenue data), plus the addendum contracts (ticker, social), Panel 4
/// ordering, the status vocabulary, and the snapshot composer. View-level
/// checks 7-11 and live acceptance 12 are Mac-side (see BUILD-NOTES).
@Suite struct DashboardStateTests {
    static let now = SnapshotAge.date("2026-11-02T15:00:00-05:00")!

    // Test 1a: the bundled fixture itself decodes against the schema.
    @Test func bundledFixtureDecodes() throws {
        let s = try DashboardStateLoader.loadBundled()
        #expect(!s.capturedAt.isEmpty)
        #expect(!s.source.isEmpty)
        #expect(!(s.briefLines ?? []).isEmpty)
        #expect(!(s.tickerItems ?? []).isEmpty)
        #expect(s.revenue != nil)
    }

    // Test 1b: a fixture with only the required fields decodes, panels empty.
    @Test func minimalFixtureDecodes() throws {
        let s = try DashboardStateLoader.decode(Data(#"{"capturedAt":"2026-11-02T15:00:00-05:00","source":"t"}"#.utf8))
        #expect(s.briefLines == nil)
        #expect(s.rankedBriefLines().isEmpty)
        #expect(s.panel4OrderedSurfaces().isEmpty)
    }

    // Test 1c: the brief kind enum is closed; an unknown kind fails decode.
    @Test func unknownBriefKindFails() {
        let json = #"{"capturedAt":"2026-11-02T15:00:00-05:00","source":"t","briefLines":[{"kind":"chatter","text":"x","sourceTag":"y"}]}"#
        #expect(throws: (any Error).self) { try DashboardStateLoader.decode(Data(json.utf8)) }
    }

    // Test 2: malformed data throws; a missing override path throws (the
    // store must surface the error, never fall back silently).
    @Test func loaderFailuresThrow() {
        #expect(throws: (any Error).self) { try DashboardStateLoader.decode(Data("not json".utf8)) }
        #expect(throws: (any Error).self) {
            try DashboardStateLoader.load(from: URL(fileURLWithPath: "/nonexistent/dashboard-state.json"))
        }
    }

    // Test 3a: ranking follows the fixed kind order regardless of file
    // order, stable within a kind.
    @Test func briefRankingOrder() {
        let s = DashboardState(capturedAt: "2026-11-02T15:00:00-05:00", source: "t", briefLines: [
            BriefLine(kind: .revenue, text: "r1", sourceTag: "s"),
            BriefLine(kind: .blocked, text: "b1", sourceTag: "s"),
            BriefLine(kind: .approval, text: "a1", sourceTag: "s"),
            BriefLine(kind: .blocked, text: "b2", sourceTag: "s"),
            BriefLine(kind: .calendar, text: "c1", sourceTag: "s"),
            BriefLine(kind: .knowledge, text: "k1", sourceTag: "s"),
        ])
        #expect(s.rankedBriefLines(limit: 10).map(\.text) == ["a1", "c1", "b1", "b2", "k1", "r1"])
    }

    // Test 3b: the cap applies after re-ranking; absent kinds leave no slot.
    @Test func briefRankingCap() {
        let lines = (1...4).map { BriefLine(kind: .revenue, text: "r\($0)", sourceTag: "s") }
            + (1...3).map { BriefLine(kind: .approval, text: "a\($0)", sourceTag: "s") }
        let s = DashboardState(capturedAt: "2026-11-02T15:00:00-05:00", source: "t", briefLines: lines)
        #expect(s.rankedBriefLines().map(\.text) == ["a1", "a2", "a3", "r1", "r2"])
    }

    // Test 4a: staleness flips at 24 hours.
    @Test func staleness() {
        let old = DashboardState(capturedAt: "2026-11-01T14:00:00-05:00", source: "t")
        let fresh = DashboardState(capturedAt: "2026-11-02T14:00:00-05:00", source: "t")
        #expect(old.isStale(now: Self.now))
        #expect(!fresh.isStale(now: Self.now))
    }

    // Test 4b: the dashboard age line is SnapshotAge's formatting, unchanged.
    @Test func ageTextMatchesSnapshotAge() {
        let s = DashboardState(capturedAt: "2026-11-02T15:00:00-05:00", source: "t")
        #expect(s.ageDescription == SnapshotAge.describe(s.capturedAt))
    }

    // Test 5: revenue strings pass through untouched, with the date.
    @Test func revenueStringsPassThrough() throws {
        let s = try DashboardStateLoader.loadBundled()
        let r = try #require(s.revenue)
        #expect(r.ladder.map(\.price) == ["$333.33", "$5,555.55", "$11,111.11", "$1,111.11/mo"])
        #expect(r.verifiedRevenueLine == "$0")
        #expect(r.verifiedRevenueAsOf == "2026-11-01")
    }

    // Addendum contracts: ticker items and the social state decode as written.
    @Test func tickerAndSocialDecode() throws {
        let json = #"""
        {"capturedAt":"2026-11-02T15:00:00-05:00","source":"t",
         "tickerItems":[{"text":"Orbit: 201 agents","sourceTag":"record","asOf":"2026-10-27"}],
         "social":{"accounts":[{"platform":"Instagram","handle":"@th3m3taway","followers":null,
             "metrics":[{"name":"views","value":"n/a","asOf":"2026-11-02"}]}],
                   "activity":[{"platform":"Instagram","stateWord":"scheduled","text":"post","when":"2026-11-03T13:00:00-05:00","sourceTag":"Postiz"}]}}
        """#
        let s = try DashboardStateLoader.decode(Data(json.utf8))
        #expect(s.tickerItems?.first?.text == "Orbit: 201 agents")
        #expect(s.social?.accounts?.first?.handle == "@th3m3taway")
        #expect(s.social?.accounts?.first?.followers == nil)
        #expect(s.social?.activity?.first?.stateWord == "scheduled")
    }

    // Panel 4 ordering: blocked first, then stale snapshots, then live.
    @Test func panel4Ordering() {
        let s = DashboardState(capturedAt: "2026-11-02T15:00:00-05:00", source: "t", surfaces: [
            SurfaceRow(name: "LiveOne", stateWord: "live", asOf: "2026-11-02T14:00:00-05:00"),
            SurfaceRow(name: "FreshSnap", stateWord: "snapshot", asOf: "2026-11-02T14:00:00-05:00"),
            SurfaceRow(name: "StaleSnap", stateWord: "snapshot", asOf: "2026-10-31T14:00:00-05:00"),
            SurfaceRow(name: "BlockedOne", stateWord: "blocked", asOf: "2026-11-02T14:00:00-05:00"),
        ])
        #expect(s.panel4OrderedSurfaces(now: Self.now).map(\.name) == ["BlockedOne", "StaleSnap", "FreshSnap", "LiveOne"])
    }

    // Status vocabulary: known words map; unknown words render raw.
    @Test func statusVocabulary() {
        #expect(DashboardStatus(word: "live") == .live)
        #expect(DashboardStatus(word: "BLOCKED") == .blocked)
        #expect(DashboardStatus(word: "Snapshot") == .snapshot)
        #expect(DashboardStatus(word: "weird") == .raw("weird"))
        #expect(DashboardStatus(word: "weird").word == "weird")
        #expect(DashboardStatus.live.slotHex == DashboardTokens.standard.success)
        #expect(DashboardStatus.blocked.slotHex == DashboardTokens.standard.bad)
    }

    // Composer: a known pending count leads the ticker; the JARVIS row is
    // written from the model probe only.
    @Test func composerKnownPending() {
        let base = DashboardState(capturedAt: "2026-11-02T10:00:00-05:00", source: "t",
            tickerItems: [TickerItem(text: "Orbit: 201 agents", sourceTag: "record", asOf: "2026-10-27")])
        let status = JarvisStatus(
            runtime: .ok(RuntimeHealth(ok: true, service: "agent-runtime", mcp: true, copilotRuntime: "available", copilot: nil)),
            rea: .ok(ReaHealth(ok: true, service: "rea-mcp", skills: 10, extensions: 2, pending: 3)),
            models: .ok(ModelRoute(default: .init(provider: "ollama", model: "muse-glimmer:30b-mlx", paid: false, why: nil),
                                   fallback: nil, toggles: [:], jev: nil, metaKeyPresent: nil)),
            skills: .offline("n/a"), checkedAt: Date())
        let out = DashboardSnapshotComposer.compose(base: base, status: status, capturedAt: "2026-11-02T15:00:00-05:00")
        #expect(out.tickerItems?.first?.text == "Approvals pending: 3")
        #expect(out.tickerItems?.count == 2)
        #expect(out.surfaces?.first?.name == "JARVIS")
        #expect(out.surfaces?.first?.note?.contains("muse-glimmer:30b-mlx") == true)
    }

    // Composer: an unreadable pending count composes as Unknown, never 0,
    // and an older approvals ticker item is replaced, not duplicated.
    @Test func composerUnknownPending() {
        let base = DashboardState(capturedAt: "2026-11-02T10:00:00-05:00", source: "t",
            tickerItems: [TickerItem(text: "Approvals pending: 9", sourceTag: "rea-mcp /health", asOf: "2026-11-02T10:00:00-05:00")])
        let status = JarvisStatus(runtime: .offline("down"), rea: .offline("down"),
                                  models: .offline("down"), skills: .offline("down"), checkedAt: Date())
        let out = DashboardSnapshotComposer.compose(base: base, status: status, capturedAt: "2026-11-02T15:00:00-05:00")
        #expect(out.tickerItems == [TickerItem(text: "Approvals pending: Unknown", sourceTag: "rea-mcp /health", asOf: "2026-11-02T15:00:00-05:00")])
    }
}

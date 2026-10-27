import Testing
import Foundation
@testable import ConsoleCore

actor Counter { var n = 0; func inc() { n += 1 } }
struct Auth: OwnerAuthenticator { let ok: Bool; func authenticate(reason: String) async -> Bool { ok } }

@MainActor @Suite struct JevGateTests {
    @Test func approveRunsExactlyOnce() async {
        let c = Counter(); let g = ApprovalGate(auth: Auth(ok: true), rules: [])
        let a = GatedAction(title: "Launch", detail: "") { await c.inc() }
        g.enqueue(a); g.enqueue(a)
        #expect(await g.approve(a.id) == .approved)
        #expect(await g.approve(a.id) == nil); #expect(g.deny(a.id) == nil); g.enqueue(a); #expect(g.pending.isEmpty)
        #expect(await c.n == 1)
    }
    @Test func concurrentApproveRunsOnce() async {
        let c = Counter(); let g = ApprovalGate(auth: Auth(ok: true), rules: [.init(name: "nexos", dailyUSDCap: 5)])
        let a = GatedAction(title: "Paid", detail: "", provider: "nexos", costUSD: 1) { await c.inc() }
        g.enqueue(a); async let x = g.approve(a.id); async let y = g.approve(a.id); _ = await (x, y)
        #expect(await c.n == 1)
    }
    @Test func denyNeverRuns() async {
        let c = Counter(); let g = ApprovalGate(auth: Auth(ok: true), rules: [])
        let a = GatedAction(title: "x", detail: "") { await c.inc() }
        g.enqueue(a); #expect(g.deny(a.id) == .denied); #expect(await g.approve(a.id) == nil); #expect(await c.n == 0)
    }
    @Test func paidOverCapBlocked() async {
        let c = Counter(); let g = ApprovalGate(auth: Auth(ok: true), rules: [.init(name: "nexos", dailyUSDCap: 0)])
        let a = GatedAction(title: "x", detail: "", provider: "nexos", costUSD: 0.1) { await c.inc() }
        g.enqueue(a); #expect(await g.approve(a.id) == .blocked); #expect(await c.n == 0)
    }
    @Test func authFailureKeepsPendingAndDoesNotRun() async {
        let c = Counter(); let g = ApprovalGate(auth: Auth(ok: false), rules: [.init(name: "nexos", dailyUSDCap: 5)])
        let a = GatedAction(title: "x", detail: "", provider: "nexos", costUSD: 1) { await c.inc() }
        g.enqueue(a); #expect(await g.approve(a.id) == .authFailed); #expect(g.pending.count == 1); #expect(await c.n == 0)
    }
    @Test func verdicts() {
        #expect(JevGate.verdict(costUSD: 0, rule: nil) == .allow)
        if case .blocked = JevGate.verdict(costUSD: 1, rule: nil) {} else { Issue.record("unknown provider must block") }
        #expect(JevGate.verdict(costUSD: 1, rule: .init(name: "n", dailyUSDCap: 2)) == .needsOwner)
    }
    @Test func rulesLoadFromDir() throws {
        let d = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString); try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        try Data(#"{"daily_usd_cap": 3}"#.utf8).write(to: d.appending(path: "nexos.json"))
        #expect(JevGate.loadRules(from: d) == [.init(name: "nexos", dailyUSDCap: 3)])
    }
    @Test func embedsLoopbackOnly() {
        #expect(EmbeddedApp.all.allSatisfy { EmbeddedApp.isLoopback($0.url(port: $0.defaultPort)) })
        #expect(!EmbeddedApp.isLoopback(URL(string: "http://2.25.168.100/")!))
    }
}

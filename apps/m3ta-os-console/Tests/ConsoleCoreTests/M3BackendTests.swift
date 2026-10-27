import Testing
import Foundation
@testable import ConsoleCore

struct OK: Authenticator { func authenticate(reason: String) async -> String? { nil } }
struct NoAuth: Authenticator { func authenticate(reason: String) async -> String? { "cancelled" } }
/// Fake signer: writes approvals/<hash>.json like jev-approve would.
struct FakeSigner: ApprovalSigner { let dir: URL
    func sign(hash: String) async -> String? {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? Data(#"{"id":"x","hash":"\#(hash)","exp":1,"sig":"s"}"#.utf8).write(to: dir.appending(path: "\(hash).json")); return nil }
}
/// Fake jevd with the real single-use semantics.
final class FakeJEV: JEVConsumer, @unchecked Sendable { var used = Set<String>(); let l = NSLock()
    func consume(hash: String, approval: String) -> GateResult { l.lock(); defer { l.unlock() }
        if used.contains(hash) { return .blocked("JEV refused: approval already used") }; used.insert(hash); return .pass(id: "id-\(hash.prefix(4))") }
}
final class Counter: @unchecked Sendable { var n = 0; let l = NSLock(); func inc() { l.lock(); n += 1; l.unlock() } }

func tmp() -> (ApprovalInbox, URL) {
    let root = FileManager.default.temporaryDirectory.appending(path: "m3-\(UUID().uuidString)")
    return (ApprovalInbox(paths: JEVPaths(root: root), ledger: DecisionLedger(url: root.appending(path: "decisions.jsonl"))), root)
}

@Suite struct ApprovalTests {
    @Test func hashMatchesJEVHook() throws {
        #expect(try ActionHash.of(tool: "console.restart_service", input: ["label": "com.m3ta.ollama-host", "b": "x/y \"q\""]) == "3c4cc3b46bc36c8b093ea2ade52c0a3efd6235b9c7eecbb152bb4572950892be")
        #expect(throws: InboxError.nonASCII) { try ActionHash.of(tool: "t", input: ["k": "é"]) }
    }
    @Test func approveRunsExactlyOnce() async throws {
        let (inbox, _) = tmp(); let a = try inbox.hold(tool: HealthChecker.restartTool, input: ["label": "com.m3ta.ollama-host"])
        #expect(inbox.pending().map(\.hash) == [a.hash])
        try await inbox.approve(a.hash, auth: OK(), signer: FakeSigner(dir: inbox.paths.approvals))
        #expect(inbox.pending().isEmpty)
        let runner = ActionRunner(inbox: inbox, gate: FakeJEV()); let c = Counter()
        #expect(runner.run(a.hash) { _ in c.inc() } == .ran)
        #expect(runner.run(a.hash) { _ in c.inc() } == .blocked("already executed"))
        await #expect(throws: InboxError.alreadyDecided(.executed)) { try await inbox.approve(a.hash, auth: OK(), signer: FakeSigner(dir: inbox.paths.approvals)) }
        #expect(c.n == 1)
    }
    @Test func concurrentRunsStillOnce() async throws {
        let (inbox, _) = tmp(); let a = try inbox.hold(tool: HealthChecker.restartTool, input: ["label": "com.m3ta.x"])
        try await inbox.approve(a.hash, auth: OK(), signer: FakeSigner(dir: inbox.paths.approvals))
        let runner = ActionRunner(inbox: inbox, gate: FakeJEV()); let c = Counter()
        await withTaskGroup(of: Void.self) { g in for _ in 0..<8 { g.addTask { _ = runner.run(a.hash) { _ in c.inc() } } } }
        #expect(c.n == 1)
    }
    @Test func denyNeverRuns() async throws {
        let (inbox, _) = tmp(); let a = try inbox.hold(tool: HealthChecker.restartTool, input: ["label": "com.m3ta.y"])
        try inbox.deny(a.hash)
        #expect(throws: InboxError.alreadyDecided(.denied)) { try inbox.deny(a.hash) }
        await #expect(throws: InboxError.alreadyDecided(.denied)) { try await inbox.approve(a.hash, auth: OK(), signer: FakeSigner(dir: inbox.paths.approvals)) }
        let c = Counter()
        #expect(ActionRunner(inbox: inbox, gate: FakeJEV()).run(a.hash) { _ in c.inc() } == .blocked("already denied"))
        #expect(c.n == 0)
    }
    @Test func failedTouchIDRecordsNothing() async throws {
        let (inbox, _) = tmp(); let a = try inbox.hold(tool: HealthChecker.restartTool, input: ["label": "com.m3ta.z"])
        await #expect(throws: InboxError.authFailed("cancelled")) { try await inbox.approve(a.hash, auth: NoAuth(), signer: FakeSigner(dir: inbox.paths.approvals)) }
        #expect(inbox.ledger.latest(a.hash) == nil); #expect(inbox.pending().count == 1)
        #expect(ActionRunner(inbox: inbox, gate: FakeJEV()).run(a.hash) { _ in } == .blocked("not approved"))
    }
    @Test func jevUnreachableFailsClosed() async throws {
        let (inbox, _) = tmp(); let a = try inbox.hold(tool: HealthChecker.restartTool, input: ["label": "com.m3ta.w"])
        try await inbox.approve(a.hash, auth: OK(), signer: FakeSigner(dir: inbox.paths.approvals))
        let c = Counter()
        let r = ActionRunner(inbox: inbox, gate: JEVSocketGate(socketPath: "/tmp/no-such-jevd-\(UUID().uuidString).sock")).run(a.hash) { _ in c.inc() }
        guard case .blocked(let why) = r else { Issue.record("should block"); return }
        #expect(why.contains("JEV unreachable")); #expect(c.n == 0)
        #expect(inbox.ledger.latest(a.hash) == .blocked)
    }
    @Test func readsJEVHookPendingFormat() throws {
        let (inbox, _) = tmp(); try FileManager.default.createDirectory(at: inbox.paths.pending, withIntermediateDirectories: true)
        let h = String(repeating: "a", count: 64)
        try Data(#"{"tool":"mcp__x__send","kind":"hard_rule:unconfirmed_send (no approval)","summary":"{\"token\": \"<redacted>\"}","at":"1793087821"}"#.utf8).write(to: inbox.paths.pending.appending(path: "\(h).json"))
        let p = inbox.pending(); #expect(p.count == 1); #expect(p[0].at == 1793087821); #expect(!p[0].consoleOwned)
        #expect(ActionRunner(inbox: inbox, gate: FakeJEV()).run(h) { _ in } == .blocked("not a console action"))
    }
}

struct FakeProber: HealthProber {
    func http(port: Int, path: String) async -> (Bool, String) { (port == 11434, "HTTP \(port == 11434 ? 200 : 0)") }
    func socketExists(_ path: String) -> Bool { false }
    func launchdRunning(_ label: String) -> (Bool, String) { (true, "launchd: running") }
}

@Suite struct HealthTests {
    @Test func protectedServicesNeverRestartable() {
        for s in Services.defaults where ["jarvis-runtime", "jarvis-rea", "waypoint", "jevd", "console-backend"].contains(s.id) { #expect(!RestartPolicy.canRestart(s), "\(s.id)") }
        #expect(!RestartPolicy.canRestart(.init(id: "pc", name: "Paperclip", probe: .launchd, launchdLabel: "com.th3m3taway.paperclip-tunnel")))
        #expect(!RestartPolicy.canRestart(.init(id: "sp", name: "x", probe: .launchd, launchdLabel: "screenpipe")))
        #expect(!RestartPolicy.canRestart(.init(id: "ts", name: "x", probe: .launchd, launchdLabel: "com.m3ta.tailscale")))
        #expect(!RestartPolicy.canRestart(.init(id: "g", name: "Google", probe: .launchd, launchdLabel: "com.google.keystone.agent")))
        #expect(RestartPolicy.canRestart(Services.defaults.first { $0.id == "ollama" }!))
    }
    @Test func checkAllLogs() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "h-\(UUID().uuidString).jsonl")
        let r = await HealthChecker(prober: FakeProber(), log: HealthLog(url: url)).checkAll()
        #expect(r.count == Services.defaults.count); #expect(r.first { $0.id == "ollama" }?.up == true); #expect(r.first { $0.id == "jevd" }?.up == false)
        #expect(try String(contentsOf: url, encoding: .utf8).contains("health_check"))
    }
    @Test func restartRequestGoesThroughInbox() throws {
        let (inbox, _) = tmp(); let url = FileManager.default.temporaryDirectory.appending(path: "h-\(UUID().uuidString).jsonl")
        let hc = HealthChecker(prober: FakeProber(), log: HealthLog(url: url))
        #expect(try hc.requestRestart("waypoint", inbox: inbox) == nil)
        #expect(try hc.requestRestart("jarvis-rea", inbox: inbox) == nil)
        let a = try #require(try hc.requestRestart("ollama", inbox: inbox))
        #expect(a.input?["label"] == "com.m3ta.ollama-host"); #expect(inbox.pending().count == 1)
        #expect(try String(contentsOf: url, encoding: .utf8).contains("restart_refused"))
    }
}

@Suite struct SkillAndBackendTests {
    @Test func skillSearch() {
        let e = SkillIndex.parse("---\nname: orbit-operations\ndescription: \"Use when reading Orbit tasks\"\n---\nbody", path: "/x/orbit/SKILL.md")
        #expect(e.name == "orbit-operations"); #expect(e.summary == "Use when reading Orbit tasks")
        let all = [e, SkillEntry(name: "voice", summary: "speak orbit summary", path: "/y")]
        #expect(SkillIndex.search("orbit", in: all).map(\.name) == ["orbit-operations", "voice"])
        #expect(SkillIndex.search("orbit tasks", in: all).count == 1)
    }
    @Test func backendLoopbackOnly() async throws {
        let (inbox, _) = tmp()
        let s = LoopbackServer(handler: ConsoleBackend.handler(inbox: inbox, health: HealthChecker(specs: [], prober: FakeProber(), log: HealthLog(url: FileManager.default.temporaryDirectory.appending(path: "b.jsonl")))))
        let port = try await s.start(port: 0); defer { s.stop() }
        let (d, r) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(port)/health")!)
        #expect((r as? HTTPURLResponse)?.statusCode == 200); #expect(String(decoding: d, as: UTF8.self).contains("m3ta-os-console"))
        var post = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/api/inbox")!); post.httpMethod = "POST"
        #expect(((try await URLSession.shared.data(for: post)).1 as? HTTPURLResponse)?.statusCode == 405)
    }
}

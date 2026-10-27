import Testing
import Foundation
@testable import ConsoleCore

final class FakeTransport: McpTransport, @unchecked Sendable {
    var responses: [String: (String, Int)] = [:]; var calls: [(URL, String)] = []
    let lock = NSLock()
    func post(_ url: URL, body: Data, headers: [String: String]) async throws -> (Data, Int) {
        let b = String(data: body, encoding: .utf8) ?? ""
        lock.withLock { calls.append((url, b)) }
        let key = responses.keys.first { b.contains($0) || url.path.contains($0) } ?? ""
        let r = responses[key] ?? ("{}", 500)
        return (Data(r.0.utf8), r.1)
    }
}
struct AllowAuth: OwnerAuthenticator { let ok: Bool; func authenticate(reason: String) async -> Bool { ok } }

@Suite struct ReaMcpClientTests {
    @Test func loopbackOrTailnetOnly() {
        #expect(ReaMcpClient.allowed(URL(string: "http://127.0.0.1:9783/mcp")!))
        #expect(!ReaMcpClient.allowed(URL(string: "http://0.0.0.0:9783/mcp")!))
        #expect(!ReaMcpClient.allowed(URL(string: "http://mac.tail1.ts.net/mcp")!))
        #expect(ReaMcpClient.allowed(URL(string: "https://mac.tail1.ts.net/rea/mcp")!))
        #expect(!ReaMcpClient.allowed(URL(string: "https://example.com/mcp")!))
        #expect(throws: ReaMcpError.notLoopback) { try ReaMcpClient(url: URL(string: "http://192.168.1.2:9783/mcp")!) }
    }
    @Test func unwrapJsonAndSse() throws {
        let j = #"{"jsonrpc":"2.0","id":1,"result":{"tools":[]}}"#
        #expect(try ReaMcpClient.unwrap(Data(j.utf8))["tools"] != nil)
        #expect(try ReaMcpClient.unwrap(Data("event: message\ndata: \(j)\n\n".utf8))["tools"] != nil)
        #expect(throws: ReaMcpError.rpc("nope")) { try ReaMcpClient.unwrap(Data(#"{"jsonrpc":"2.0","id":1,"error":{"code":-1,"message":"nope"}}"#.utf8)) }
    }
    @Test func listsTools() async throws {
        let t = FakeTransport(); t.responses[#"tools\/list"#] = (#"{"jsonrpc":"2.0","id":1,"result":{"tools":[{"name":"rea_orbit_status"},{"name":"rea_orbit_message"}]}}"#, 200)
        let tools = try await ReaMcpClient.mac(transport: t).listTools()
        #expect(tools.map(\.name) == ["rea_orbit_status", "rea_orbit_message"])
    }
    @Test func refusesWriteTools() async {
        let t = FakeTransport()
        let c = ReaMcpClient.mac(transport: t)
        for w in ["rea_orbit_message", "rea_orbit_upsert_row", "rea_skills_run", "rea_clianything_call", "rea_hyperagent_call", "rea_audit_run"] {
            await #expect(throws: ReaMcpError.notReadOnly(w)) { _ = try await c.callRead(w) }
        }
        #expect(t.calls.isEmpty) // nothing was ever sent
    }
    @Test func searchSkillsDecodes() async throws {
        let t = FakeTransport()
        t.responses["rea_skills_search"] = (#"{"jsonrpc":"2.0","id":1,"result":{"structuredContent":{"ok":true,"output":{"results":[{"id":"agents:orbit","name":"orbit","description":"d","source":"agents","writes":false}]}}}}"#, 200)
        let s = try await ReaMcpClient.mac(transport: t).searchSkills("orbit")
        #expect(s.first?.id == "agents:orbit")
    }
    @Test func httpErrorSurfaces() async {
        let t = FakeTransport()
        await #expect(throws: ReaMcpError.http(500)) { _ = try await ReaMcpClient.mac(transport: t).callRead("rea_orbit_status") }
    }
}

@Suite struct ReaApprovalGatingTests {
    func make(_ t: FakeTransport) -> ReaApprovalsAPI {
        t.responses["rea_approvals_list"] = (#"{"jsonrpc":"2.0","id":1,"result":{"structuredContent":{"ok":true,"output":{"approvals":[{"id":"jev_a1","action":"supervisor.restart:x","status":"pending","createdAt":"2026-10-27T01:21:37.550Z"},{"id":"jev_old","action":"y","status":"executed"}]}}}}"#, 200)
        t.responses["/approve"] = ("{\"ok\":true}", 200); t.responses["/deny"] = ("{\"ok\":true}", 200)
        return ReaApprovalsAPI(rea: .mac(transport: t), runtimeBase: URL(string: "http://127.0.0.1:9782")!, transport: t)
    }
    @Test func onlyPendingListed() async throws {
        let p = try await make(FakeTransport()).pending()
        #expect(p.map(\.id) == ["jev_a1"])
    }
    @MainActor @Test func approveRunsExactlyOnce() async {
        let t = FakeTransport(); let inbox = ApprovalInbox(api: make(t), auth: AllowAuth(ok: true))
        await inbox.refresh()
        async let a = inbox.decide("jev_a1", .approve); async let b = inbox.decide("jev_a1", .approve)
        let r = await [a, b]
        #expect(r.filter { $0 }.count == 1)
        #expect(t.calls.filter { $0.0.path.hasSuffix("/jev_a1/approve") }.count == 1)
        #expect(await inbox.decide("jev_a1", .approve) == false)
    }
    @MainActor @Test func denyNeverRunsApprove() async {
        let t = FakeTransport(); let inbox = ApprovalInbox(api: make(t), auth: AllowAuth(ok: false))
        await inbox.refresh()
        #expect(await inbox.decide("jev_a1", .deny))
        #expect(t.calls.contains { $0.0.path.hasSuffix("/jev_a1/deny") })
        #expect(!t.calls.contains { $0.0.path.contains("/approve") })
        #expect(await inbox.decide("jev_a1", .approve) == false)
    }
    @MainActor @Test func failedAuthSendsNothing() async {
        let t = FakeTransport(); let inbox = ApprovalInbox(api: make(t), auth: AllowAuth(ok: false))
        await inbox.refresh()
        #expect(await inbox.decide("jev_a1", .approve) == false)
        #expect(!t.calls.contains { $0.0.path.contains("/approvals/") })
        #expect(inbox.items.count == 1)
    }
    @Test func rejectsOddIds() async {
        await #expect(throws: ReaMcpError.badResponse) { try await make(FakeTransport()).decide("../x", .approve) }
    }
}

import Testing
import Foundation
@testable import ConsoleCore

@Suite struct RemoteTests {
    @Test func tailnetOnly() {
        #expect(TailnetEndpoint(host: "kingdom-mac.tail1234.ts.net") != nil)
        for bad in ["0.0.0.0", "127.0.0.1", "example.com", "evil.ts.net.example.com", "https://a.b.ts.net", "a.b.ts.net:9782", "a..ts.net", "ts.net", "-a.b.ts.net"] {
            #expect(TailnetEndpoint(host: bad) == nil, "\(bad)")
        }
    }
    @Test func tailnetURLsAreHTTPSAndPrefixed() {
        let e = TailnetEndpoint(host: "Mac.tail1.ts.net")!
        #expect(e.runtime("/health").absoluteString == "https://mac.tail1.ts.net/jarvis/health")
        #expect(e.rea("/health").absoluteString == "https://mac.tail1.ts.net/rea/health")
    }
    @Test func glance() {
        #expect(HealthGlance.from(nil, pending: 1).level == .unknown)
        let off = JarvisStatus(runtime: .offline("x"), rea: .offline("x"), models: .offline("x"), skills: .offline("x"), checkedAt: .now)
        #expect(HealthGlance.from(off, pending: 0).level == .offline)
    }
    @Test func parsePending() throws {
        let d = #"{"pending":[{"id":"a","tool":"t","kind":"paid","summary":"s","at":1},{"id":"b","tool":"t","kind":"svc","summary":"s2","at":5}]}"#.data(using: .utf8)!
        #expect(try HTTPApprovalsAPI.parse(d).map(\.id) == ["b", "a"])
    }
    struct Auth: OwnerAuthenticator { let ok: Bool; func authenticate(reason: String) async -> Bool { ok } }
    actor Spy: ApprovalsAPI {
        var calls: [String] = []
        nonisolated func pending() async throws -> [PendingApproval] { DemoApprovalsAPI.items }
        func decide(_ id: String, _ d: ApprovalDecision) async throws { calls.append("\(id):\(d.rawValue)") }
    }
    @Test @MainActor func approveOnceAndAuthGated() async {
        let spy = Spy(); let inbox = ApprovalInbox(api: spy, auth: Auth(ok: true)); await inbox.refresh()
        let id = inbox.items[0].id
        #expect(await inbox.decide(id, .approve)); #expect(!(await inbox.decide(id, .approve)))
        #expect(await spy.calls == ["\(id):approve"])
        let denied = ApprovalInbox(api: spy, auth: Auth(ok: false)); await denied.refresh()
        #expect(!(await denied.decide(id, .approve))); #expect(denied.items.count == 2)
        #expect(await denied.decide(id, .deny)) // deny needs no auth
    }
}

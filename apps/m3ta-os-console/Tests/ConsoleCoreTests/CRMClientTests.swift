import Testing
import Foundation
@testable import ConsoleCore

/// CRM module (specs/m3ta-os-console-crm.md): decoding pins against
/// payload shapes copied from the CRM's real route handlers and
/// service layer (nova-ai-crm app/api/v1 + lib/services.ts), config
/// and unbound behavior, and the write body builders. No server is
/// contacted: the unbound tests prove the client never calls out
/// without a token.
@Suite struct CRMClientTests {

    private func unbound() -> CRMConfig { CRMConfig(baseURL: CRMConfig.defaultBaseURL, token: nil, agentId: "test") }
    private func bound() -> CRMConfig { CRMConfig(baseURL: CRMConfig.defaultBaseURL, token: "t", agentId: "test") }

    // MARK: Config + unbound (CRM-001)

    @Test func unboundWhenTokenMissingOrEmpty() {
        #expect(!unbound().isBound)
        #expect(!CRMConfig(baseURL: CRMConfig.defaultBaseURL, token: "", agentId: "test").isBound)
        #expect(bound().isBound)
    }

    @Test func configResolutionEnvFirst() {
        let d = UserDefaults(suiteName: "crm-test-\(UUID())")!
        d.set("http://defaults.example:3120", forKey: "crmBaseURL")
        let fromDefaults = CRMConfig.current(env: [:], defaults: d)
        #expect(fromDefaults.baseURL.absoluteString == "http://defaults.example:3120")
        #expect(fromDefaults.token == nil)
        #expect(fromDefaults.agentId == CRMConfig.defaultAgentId)
        let fromEnv = CRMConfig.current(env: ["CRM_BASE_URL": "http://env.example:9", "CRM_API_TOKEN": "x", "CRM_AGENT_ID": "agent-1"], defaults: d)
        #expect(fromEnv.baseURL.absoluteString == "http://env.example:9")
        #expect(fromEnv.token == "x")
        #expect(fromEnv.agentId == "agent-1")
        #expect(CRMConfig.current(env: [:], defaults: UserDefaults(suiteName: "crm-test-\(UUID())")!).baseURL == CRMConfig.defaultBaseURL)
    }

    @Test func insecureRemoteBaseIsUnboundEvenWithToken() {
        // The token is full-scope; it never travels over plain http to
        // a non-loopback host (EGM F6).
        let c = CRMConfig(baseURL: URL(string: "http://crm.example.com:3120")!, token: "t", agentId: "test")
        #expect(!c.isBound); #expect(c.bindProblem?.contains("loopback or HTTPS") == true)
        #expect(CRMConfig(baseURL: URL(string: "https://crm.example.com")!, token: "t", agentId: "test").isBound)
        #expect(CRMConfig(baseURL: URL(string: "http://127.0.0.1:3120")!, token: "t", agentId: "test").isBound)
    }

    @Test func urlBuildingNormalisesTrailingSlash() {
        let c = CRMConfig(baseURL: URL(string: "http://localhost:3120/")!, token: "t", agentId: "test")
        #expect(c.url("/api/v1/summary").absoluteString == "http://localhost:3120/api/v1/summary")
    }

    @Test func postDecodesBareRowAt200() {
        // POST answers are the bare Prisma row (no includes), status
        // 200, not the GET shape (EGM F2). The GET models decode them
        // because every include is optional.
        let d = #"{"id":"t9","title":"Created","status":"open","kind":"general","dueAt":null,"contactId":null,"companyId":null,"dealId":null}"#.data(using: .utf8)!
        let t = CRMClient.decodeWrite(d, status: 200, as: CRMTask.self).value
        #expect(t?.title == "Created"); #expect(t?.contact == nil)
    }

    @Test func unboundReadsReturnUnboundWithoutNetwork() async {
        let c = CRMClient(config: unbound())
        #expect(await c.summary() == .offline(CRMConfig.unboundReason))
        #expect(await c.companies() == .offline(CRMConfig.unboundReason))
        #expect(await c.createContact(CRMNewContact(fullName: "X")) == .offline(CRMConfig.unboundReason))
        let snap = await c.loadAll()
        #expect(snap.fullyOffline)
        #expect(snap.rosterCount == nil)
    }

    // MARK: Read decoding

    @Test func decodesSummary() {
        let d = #"{"openDeals":3,"pipelineValue":12000,"wonDeals":1,"wonValue":2500,"lostDeals":2,"contacts":25,"companies":25,"byStage":{"Discovery":{"count":2,"value":7000},"Proposal":{"count":1,"value":5000}}}"#.data(using: .utf8)!
        let s = CRMClient.decodeRead(d, status: 200, as: CRMSummary.self).value
        #expect(s?.openDeals == 3); #expect(s?.pipelineValue == 12000)
        #expect(s?.byStage["Discovery"]?.count == 2); #expect(s?.byStage["Proposal"]?.value == 5000)
    }

    @Test func decodesCompaniesWithUnderscoreCount() {
        // The rollup rides under `_count`. A model reading `counts`
        // would decode silently empty; this fixture pins the real key.
        let d = #"[{"id":"c1","name":"Builder Brokerz","slug":"builder-brokerz","type":"partner","status":"active","website":null,"notes":null,"source":"client-matrix","createdAt":"2026-11-06T16:45:00.000Z","updatedAt":"2026-11-06T16:45:00.000Z","_count":{"contacts":4,"deals":2,"tasks":7,"snapshots":1}},{"id":"c2","name":"Solo Co","slug":"solo-co","type":"client","status":"active","source":"manual"}]"#.data(using: .utf8)!
        let rows = CRMClient.decodeRead(d, status: 200, as: [CRMCompany].self).value
        #expect(rows?.count == 2)
        #expect(rows?.first?.counts?.contacts == 4); #expect(rows?.first?.counts?.tasks == 7)
        #expect(rows?.last?.counts == nil)
    }

    @Test func decodesContactWithNestedCompany() {
        let d = #"[{"id":"p1","firstName":"Sardo","lastName":null,"fullName":"Sardo","email":"sardonyxnext@gmail.com","phone":null,"companyId":"c1","companyName":"Sardo Co","status":"active","lifecycleStage":"lead","engagementScore":3,"isStarred":false,"lastActivityAt":null,"source":"manual","createdAt":"2026-11-01T10:00:00.000Z","updatedAt":"2026-11-05T10:00:00.000Z","company":{"id":"c1","name":"Sardo Co","slug":"sardo-co","type":"client","status":"active"}}]"#.data(using: .utf8)!
        let rows = CRMClient.decodeRead(d, status: 200, as: [CRMContact].self).value
        #expect(rows?.first?.fullName == "Sardo")
        #expect(rows?.first?.companyDisplayName == "Sardo Co")
        // Server rule: lastActivityAt ?? updatedAt.
        #expect(rows?.first?.lastActivity == "2026-11-05T10:00:00.000Z")
    }

    @Test func decodesTaskRowsAndIgnoresAssigneeExtras() {
        // Followups and tasks are the same row shape. The assignee
        // arrives as the full Prisma user object; the client decodes
        // id + name only and succeeds with the rest present.
        let d = #"[{"id":"t1","title":"Send the MyGLP deck","description":null,"status":"open","priority":"normal","kind":"follow_up","dueAt":"2026-11-05T17:00:00.000Z","completedAt":null,"contactId":"p1","companyId":"c1","dealId":null,"contact":{"id":"p1","fullName":"Sardo"},"company":{"id":"c1","name":"Sardo Co","slug":"sardo-co"},"deal":null,"assignee":{"id":"u1","name":"M3ta","email":"x@example.com","passwordHash":"never-decoded","role":"owner"}}]"#.data(using: .utf8)!
        let rows = CRMClient.decodeRead(d, status: 200, as: [CRMTask].self).value
        #expect(rows?.first?.title == "Send the MyGLP deck")
        #expect(rows?.first?.contact?.fullName == "Sardo")
        #expect(rows?.first?.assignee?.name == "M3ta")
        #expect(rows?.first?.isOverdue(now: CRMDate.parse("2026-11-06T12:00:00.000Z")!) == true)
        #expect(rows?.first?.isOverdue(now: CRMDate.parse("2026-11-04T12:00:00.000Z")!) == false)
    }

    @Test func decodesRetention() {
        let d = #"{"days":14,"cutoff":"2026-10-23T16:45:00.000Z","cold":[{"id":"p9","fullName":"Cold One","updatedAt":"2026-10-01T09:00:00.000Z"}]}"#.data(using: .utf8)!
        let r = CRMClient.decodeRead(d, status: 200, as: CRMRetention.self).value
        #expect(r?.days == 14); #expect(r?.cold.count == 1)
        #expect(r?.cold.first?.lastActivity == "2026-10-01T09:00:00.000Z")
    }

    @Test func non200AndGarbageAreOffline() {
        let ok = #"{}"#.data(using: .utf8)!
        #expect(CRMClient.decodeRead(ok, status: 401, as: CRMSummary.self) == .offline("HTTP 401"))
        #expect(CRMClient.decodeRead(ok, status: 503, as: CRMSummary.self) == .offline("HTTP 503"))
        #expect(CRMClient.decodeRead(Data("<html>".utf8), status: 200, as: CRMSummary.self) == .offline("unexpected response"))
    }

    // MARK: Dates

    @Test func crmDatesParseFractionalSeconds() {
        // Prisma's format. SnapshotAge.date returns nil for these;
        // CRMDate must not.
        #expect(CRMDate.parse("2026-11-06T16:45:00.000Z") != nil)
        #expect(CRMDate.parse("2026-11-06T16:45:00Z") != nil)
        #expect(CRMDate.parse(nil) == nil); #expect(CRMDate.parse("") == nil); #expect(CRMDate.parse("soon") == nil)
    }

    // MARK: Write seams (CRM-005, CRM-006)

    @Test func contactBodyOmitsUnsetFields() {
        let body = CRMClient.encodeBody(CRMNewContact(fullName: "Test Person"))
        let j = try! JSONSerialization.jsonObject(with: body) as! [String: Any]
        #expect(j["fullName"] as? String == "Test Person")
        #expect(j["email"] == nil); #expect(j["phone"] == nil); #expect(j["companyName"] == nil)
        let full = CRMClient.encodeBody(CRMNewContact(fullName: "A B", email: "a@b.c", companyName: "Co"))
        let j2 = try! JSONSerialization.jsonObject(with: full) as! [String: Any]
        #expect(j2["email"] as? String == "a@b.c"); #expect(j2["companyName"] as? String == "Co")
    }

    @Test func taskBodyEncodesDueDate() {
        let due = CRMDate.parse("2026-11-07T17:00:00.000Z")!
        let body = CRMClient.encodeBody(CRMNewTask(title: "Call back", kind: "follow_up", dueAt: due))
        let j = try! JSONSerialization.jsonObject(with: body) as! [String: Any]
        #expect(j["title"] as? String == "Call back"); #expect(j["kind"] as? String == "follow_up")
        #expect((j["dueAt"] as? String)?.contains("2026-11-07") == true)
        #expect(j["contactId"] == nil)
    }

    @Test func writeDecodeSurfacesServerErrorText() {
        let err = #"{"error":"fullName required"}"#.data(using: .utf8)!
        #expect(CRMClient.decodeWrite(err, status: 400, as: CRMContact.self) == .offline("HTTP 400: fullName required"))
        let created = #"{"id":"p2","fullName":"Test Person"}"#.data(using: .utf8)!
        #expect(CRMClient.decodeWrite(created, status: 201, as: CRMContact.self).value?.fullName == "Test Person")
    }

    @Test func emptyNamesNeverWrite() async {
        let c = CRMClient(config: bound())
        #expect(await c.createContact(CRMNewContact(fullName: "   ")) == .offline("fullName required"))
        #expect(await c.createTask(CRMNewTask(title: "")) == .offline("title required"))
    }

    // MARK: Snapshot + store (CRMState)

    @Test func snapshotCountsAreNilWhenOfflineNeverZero() {
        let snap = CRMSnapshot(summary: .offline("HTTP 503"), companies: .offline("HTTP 503"),
                               followUps: .offline("HTTP 503"), retention: .offline("HTTP 503"),
                               tasks: .offline("HTTP 503"), checkedAt: Date())
        #expect(snap.fullyOffline)
        #expect(snap.rosterCount == nil); #expect(snap.followUpsDueCount == nil)
        #expect(snap.retentionAlertCount == nil); #expect(snap.openTaskCount == nil)
        let mixed = CRMSnapshot(summary: .offline("x"), companies: .ok([]), followUps: .ok([]),
                                retention: .offline("x"), tasks: .offline("x"), checkedAt: Date())
        #expect(!mixed.fullyOffline)
        #expect(mixed.rosterCount == 0)
    }

    @Test @MainActor func storeStaysSnapshotlessWhileUnbound() async {
        let s = CRMStore(config: unbound())
        #expect(!s.isBound)
        await s.refresh()
        #expect(s.snapshot == nil)
    }
}

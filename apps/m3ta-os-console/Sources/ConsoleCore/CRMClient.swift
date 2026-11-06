import Foundation

/// CRM module (spec: specs/m3ta-os-console-crm.md): client for the
/// M3ta-CRM machine API at /api/v1/* (contract: nova-ai-crm
/// docs/INTEGRATIONS.md + integration.manifest.json, verified
/// 2026-11-06). Follows the JarvisClient pattern: reads answer a
/// `Probe` (200 + decodable, else offline with a reason); writes answer
/// 200/201 or offline with the server's own error text.
///
/// The bearer token comes from the CRM_API_TOKEN environment variable
/// only. It is never hardcoded, never written to UserDefaults, a plist,
/// or a fixture. Token unset means UNBOUND: reads return the unbound
/// reason without any network call, and the tab renders the unbound
/// screen (CRM-001). Unbound is a detectable state, never a silent
/// empty roster.

// MARK: - Config

public struct CRMConfig: Sendable, Equatable {
    public var baseURL: URL
    public var token: String?
    public var agentId: String

    public init(baseURL: URL, token: String?, agentId: String) {
        self.baseURL = baseURL; self.token = token; self.agentId = agentId
    }

    public static let defaultBaseURL = URL(string: "http://localhost:3120")!
    public static let defaultAgentId = "m3ta-os-console"
    public static let unboundReason = "unbound: CRM_API_TOKEN not set in the app environment"

    /// Bound requires a non-empty token. An empty string is not a token.
    public var isBound: Bool { bindProblem == nil }

    /// The token is a full-scope credential for every /api/v1/* route,
    /// so it only ever travels to a loopback base URL or an HTTPS one.
    /// A plain-http non-loopback base URL leaves the module unbound
    /// with this reason, whatever the token (EGM resolution, F6).
    public var isSecureBase: Bool {
        if baseURL.scheme == "https" { return true }
        guard baseURL.scheme == "http" else { return false }
        let h = baseURL.host ?? ""
        return h == "localhost" || h == "127.0.0.1" || h == "::1"
    }

    /// Why the module is unbound, in words the unbound screen renders
    /// verbatim; nil when bound.
    public var bindProblem: String? {
        if (token ?? "").isEmpty { return Self.unboundReason }
        if !isSecureBase { return "unbound: base URL \(baseURL.absoluteString) is not loopback or HTTPS; the CRM token is never sent over plain http" }
        return nil
    }

    public func url(_ path: String) -> URL {
        URL(string: baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + path)!
    }

    /// Resolution order: environment first (CRM_BASE_URL, CRM_API_TOKEN,
    /// CRM_AGENT_ID), then the Settings base-URL override (crmBaseURL).
    /// The token has no defaults route, by design.
    public static func current(env: [String: String] = ProcessInfo.processInfo.environment,
                               defaults: UserDefaults = .standard) -> CRMConfig {
        let base: URL = {
            if let s = env["CRM_BASE_URL"], let u = URL(string: s) { return u }
            if let s = defaults.string(forKey: "crmBaseURL"), !s.isEmpty, let u = URL(string: s) { return u }
            return defaultBaseURL
        }()
        let token = env["CRM_API_TOKEN"]
        let agent = env["CRM_AGENT_ID"] ?? defaultAgentId
        return CRMConfig(baseURL: base, token: token, agentId: agent.isEmpty ? defaultAgentId : agent)
    }
}

// MARK: - Dates

/// The CRM serializes Prisma DateTime values as ISO-8601 with
/// fractional seconds (e.g. 2026-11-06T16:45:00.000Z), which the
/// shared SnapshotAge parser (no fractional seconds) reads as nil.
/// Models keep the raw strings (the MeshState convention); this is
/// the one parser for display and overdue checks.
public enum CRMDate {
    public static func parse(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
    public static func isoString(_ d: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: d)
    }
}

// MARK: - Models (payload shapes per the CRM route handlers + services)

public struct CRMSummary: Codable, Sendable, Equatable {
    public var openDeals: Int
    public var pipelineValue: Double
    public var wonDeals: Int
    public var wonValue: Double
    public var lostDeals: Int
    public var contacts: Int
    public var companies: Int
    public var byStage: [String: StageRollup]
    public struct StageRollup: Codable, Sendable, Equatable {
        public var count: Int
        public var value: Double
    }
}

public struct CRMCompany: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var slug: String
    public var type: String?
    public var status: String?
    public var website: String?
    public var notes: String?
    public var source: String?
    public var createdAt: String?
    public var updatedAt: String?
    /// Rollup counts ride under the Prisma key `_count`, not `counts`.
    public var counts: Counts?
    public struct Counts: Codable, Sendable, Equatable {
        public var contacts: Int?
        public var deals: Int?
        public var tasks: Int?
        public var snapshots: Int?
    }
    enum CodingKeys: String, CodingKey {
        case id, name, slug, type, status, website, notes, source, createdAt, updatedAt
        case counts = "_count"
    }
}

public struct CRMContact: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var firstName: String?
    public var lastName: String?
    public var fullName: String
    public var email: String?
    public var phone: String?
    public var companyId: String?
    public var companyName: String?
    public var company: CRMCompany?
    public var status: String?
    public var lifecycleStage: String?
    public var engagementScore: Int?
    public var isStarred: Bool?
    public var lastActivityAt: String?
    public var source: String?
    public var createdAt: String?
    public var updatedAt: String?
    /// The server's cold rule reads lastActivityAt, falling back to
    /// updatedAt; the display rule matches it exactly.
    public var lastActivity: String? { lastActivityAt ?? updatedAt }
    public var companyDisplayName: String? { company?.name ?? companyName }
}

public struct CRMDealRef: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String?
    public var value: Double?
    public var status: String?
}

/// Assignee as decoded: id and name only. Task rows arrive with the
/// full Prisma user object; the client never holds the rest of it.
public struct CRMUserRef: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String?
}

public struct CRMTask: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var description: String?
    public var status: String?
    public var priority: String?
    public var kind: String?
    public var dueAt: String?
    public var completedAt: String?
    public var contactId: String?
    public var companyId: String?
    public var dealId: String?
    public var contact: CRMContact?
    public var company: CRMCompany?
    public var deal: CRMDealRef?
    public var assignee: CRMUserRef?
    public var dueDate: Date? { CRMDate.parse(dueAt) }
    public func isOverdue(now: Date = Date()) -> Bool {
        guard let d = dueDate else { return false }
        return d <= now && (status ?? "open") == "open"
    }
}

public struct CRMRetention: Codable, Sendable, Equatable {
    public var days: Int
    public var cutoff: String
    public var cold: [CRMContact]
}

// MARK: - Write payloads (HITL creates; bodies omit unset fields)

public struct CRMNewContact: Encodable, Sendable, Equatable {
    public var fullName: String
    public var email: String?
    public var phone: String?
    public var companyName: String?
    public init(fullName: String, email: String? = nil, phone: String? = nil, companyName: String? = nil) {
        self.fullName = fullName; self.email = email; self.phone = phone; self.companyName = companyName
    }
}

public struct CRMNewTask: Encodable, Sendable, Equatable {
    public var title: String
    public var kind: String?
    public var dueAt: String?
    public var contactId: String?
    public var companyId: String?
    public var dealId: String?
    public init(title: String, kind: String? = nil, dueAt: Date? = nil,
                contactId: String? = nil, companyId: String? = nil, dealId: String? = nil) {
        self.title = title; self.kind = kind
        self.dueAt = dueAt.map(CRMDate.isoString)
        self.contactId = contactId; self.companyId = companyId; self.dealId = dealId
    }
}

// MARK: - Client

public struct CRMClient: Sendable {
    public let config: CRMConfig
    public init(config: CRMConfig) { self.config = config }

    // Pure seams, unit-tested without a server (JarvisClient.decode pattern).

    public static func decodeRead<T: Decodable & Sendable & Equatable>(_ data: Data, status: Int, as: T.Type) -> Probe<T> {
        guard status == 200 else { return .offline("HTTP \(status)") }
        do { return .ok(try JSONDecoder().decode(T.self, from: data)) } catch { return .offline("unexpected response") }
    }

    /// Writes accept 200/201. Any other status surfaces the server's own
    /// `{"error": "..."}` text when it sends one (400 fullName/title).
    public static func decodeWrite<T: Decodable & Sendable & Equatable>(_ data: Data, status: Int, as: T.Type) -> Probe<T> {
        guard status == 200 || status == 201 else {
            if let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let msg = j["error"] as? String, !msg.isEmpty {
                return .offline("HTTP \(status): \(msg)")
            }
            return .offline("HTTP \(status)")
        }
        do { return .ok(try JSONDecoder().decode(T.self, from: data)) } catch { return .offline("unexpected response") }
    }

    public static func encodeBody<T: Encodable>(_ v: T) -> Data {
        (try? JSONEncoder().encode(v)) ?? Data()
    }

    func request(_ method: String, _ path: String, body: Data? = nil, timeout: TimeInterval = 10) -> URLRequest {
        var req = URLRequest(url: config.url(path), cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        req.httpMethod = method
        req.setValue("Bearer \(config.token ?? "")", forHTTPHeaderField: "Authorization")
        req.setValue(config.agentId, forHTTPHeaderField: "x-agent-id")
        if body != nil { req.setValue("application/json", forHTTPHeaderField: "content-type") }
        req.httpBody = body
        return req
    }

    func send<T: Decodable & Sendable & Equatable>(_ req: URLRequest, as: T.Type, write: Bool) async -> Probe<T> {
        do {
            let (data, resp) = try await JarvisClient.session(req.timeoutInterval).data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            return write ? Self.decodeWrite(data, status: code, as: T.self) : Self.decodeRead(data, status: code, as: T.self)
        } catch { return .offline(error.localizedDescription) }
    }

    func get<T: Decodable & Sendable & Equatable>(_ path: String, as: T.Type) async -> Probe<T> {
        guard config.isBound else { return .offline(config.bindProblem ?? CRMConfig.unboundReason) }
        return await send(request("GET", path), as: T.self, write: false)
    }

    // Reads

    public func summary() async -> Probe<CRMSummary> { await get("/api/v1/summary", as: CRMSummary.self) }
    public func companies() async -> Probe<[CRMCompany]> { await get("/api/v1/companies", as: [CRMCompany].self) }
    public func followups() async -> Probe<[CRMTask]> { await get("/api/v1/followups", as: [CRMTask].self) }
    public func tasks() async -> Probe<[CRMTask]> { await get("/api/v1/tasks", as: [CRMTask].self) }
    public func retention(days: Int? = nil) async -> Probe<CRMRetention> {
        await get(days.map { "/api/v1/retention?days=\($0)" } ?? "/api/v1/retention", as: CRMRetention.self)
    }
    public func contacts(query: String? = nil) async -> Probe<[CRMContact]> {
        guard let q = query, !q.isEmpty else { return await get("/api/v1/contacts", as: [CRMContact].self) }
        let enc = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q
        return await get("/api/v1/contacts?q=\(enc)", as: [CRMContact].self)
    }

    // Writes (operator-confirmed in the tab; attributed by x-agent-id)

    public func createContact(_ c: CRMNewContact) async -> Probe<CRMContact> {
        guard config.isBound else { return .offline(config.bindProblem ?? CRMConfig.unboundReason) }
        guard !c.fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .offline("fullName required") }
        return await send(request("POST", "/api/v1/contacts", body: Self.encodeBody(c)), as: CRMContact.self, write: true)
    }
    public func createTask(_ t: CRMNewTask) async -> Probe<CRMTask> {
        guard config.isBound else { return .offline(config.bindProblem ?? CRMConfig.unboundReason) }
        guard !t.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .offline("title required") }
        return await send(request("POST", "/api/v1/tasks", body: Self.encodeBody(t)), as: CRMTask.self, write: true)
    }

    /// One refresh = the five reads, concurrent. Each keeps its own
    /// Probe so one failed read never blanks the others.
    public func loadAll() async -> CRMSnapshot {
        async let s = summary()
        async let c = companies()
        async let f = followups()
        async let r = retention()
        async let t = tasks()
        return CRMSnapshot(summary: await s, companies: await c, followUps: await f,
                           retention: await r, tasks: await t, checkedAt: Date())
    }
}

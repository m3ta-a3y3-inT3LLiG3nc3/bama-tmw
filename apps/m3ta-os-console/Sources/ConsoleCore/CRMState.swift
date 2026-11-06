import Foundation
import Observation

/// CRM module state (spec: specs/m3ta-os-console-crm.md). The snapshot
/// is the five machine-API reads from one refresh, each kept as its
/// own Probe: a failed read shows its reason in its own panel and
/// never blanks or zeroes the others. Count helpers return nil
/// (unknown) while a probe is offline, never zero: unknown stays
/// unknown, per the DashboardState discipline.
public struct CRMSnapshot: Sendable, Equatable {
    public var summary: Probe<CRMSummary>
    public var companies: Probe<[CRMCompany]>
    public var followUps: Probe<[CRMTask]>
    public var retention: Probe<CRMRetention>
    public var tasks: Probe<[CRMTask]>
    public var checkedAt: Date

    public init(summary: Probe<CRMSummary>, companies: Probe<[CRMCompany]>,
                followUps: Probe<[CRMTask]>, retention: Probe<CRMRetention>,
                tasks: Probe<[CRMTask]>, checkedAt: Date) {
        self.summary = summary; self.companies = companies
        self.followUps = followUps; self.retention = retention
        self.tasks = tasks; self.checkedAt = checkedAt
    }

    public var rosterCount: Int? { companies.value?.count }
    public var followUpsDueCount: Int? { followUps.value?.count }
    public var retentionAlertCount: Int? { retention.value?.cold.count }
    public var openTaskCount: Int? { tasks.value?.count }
    /// Every read failed (bound, but nothing answered): the tab's
    /// offline face, distinct from the unbound face.
    public var fullyOffline: Bool {
        summary.value == nil && companies.value == nil && followUps.value == nil
            && retention.value == nil && tasks.value == nil
    }
}

/// Owns the CRM config and the current snapshot, mirroring
/// DashboardStore: refresh replaces the snapshot wholesale, an
/// unbound config produces no snapshot and no network call, and no
/// stale snapshot is ever substituted silently. In ConsoleCore (not
/// the app target) so the iOS companion shares it, per the stage-4
/// pattern.
@MainActor @Observable
public final class CRMStore {
    public var config: CRMConfig
    public private(set) var snapshot: CRMSnapshot?
    public private(set) var isRefreshing = false
    /// Last write outcome, rendered by the create forms: the created
    /// row's name on success, the server's reason on failure.
    public var lastWrite: Probe<String>?

    public init(config: CRMConfig = .current()) { self.config = config }

    public var isBound: Bool { config.isBound }
    public var client: CRMClient { CRMClient(config: config) }

    public func refresh() async {
        guard config.isBound else { snapshot = nil; return }
        isRefreshing = true
        snapshot = await client.loadAll()
        isRefreshing = false
    }

    @discardableResult
    public func createContact(_ c: CRMNewContact) async -> Probe<CRMContact> {
        let r = await client.createContact(c)
        switch r {
        case .ok(let v): lastWrite = .ok("Contact created: \(v.fullName)")
        case .offline(let w): lastWrite = .offline(w)
        }
        if r.value != nil { await refresh() }
        return r
    }

    @discardableResult
    public func createTask(_ t: CRMNewTask) async -> Probe<CRMTask> {
        let r = await client.createTask(t)
        switch r {
        case .ok(let v): lastWrite = .ok("Task created: \(v.title)")
        case .offline(let w): lastWrite = .offline(w)
        }
        if r.value != nil { await refresh() }
        return r
    }
}

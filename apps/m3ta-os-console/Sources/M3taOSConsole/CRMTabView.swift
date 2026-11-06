import SwiftUI
import ConsoleCore

/// CRM tab (spec: specs/m3ta-os-console-crm.md): the native face of
/// M3ta-CRM inside the dashboard. Reads ride the tab's own refresh
/// loop (the dashboard's on-open probe set for the other tabs is
/// unchanged); the tab renders exactly three faces and no fourth:
/// unbound (no token in the environment), offline (bound, nothing
/// answered), and live (each panel its own Probe). Writes happen only
/// from the two create forms, on the operator's confirm tap.
struct CRMTabView: View {
    @State private var crm = CRMStore()
    @AppStorage("jarvisRefreshSeconds") private var refreshSeconds = 10
    @State private var appeared = false

    @State private var contactName = ""
    @State private var contactEmail = ""
    @State private var contactPhone = ""
    @State private var contactCompany = ""
    @State private var taskTitle = ""
    @State private var taskKind = "follow_up"
    @State private var taskHasDue = false
    @State private var taskDue = Date()
    @State private var writing = false
    /// The server's task kinds (Prisma schema). follow_up and retention
    /// are the kinds the follow-ups route surfaces; a free-typed kind
    /// would create tasks that vanish from that panel (EGM F17).
    private let taskKinds = ["follow_up", "retention", "general", "appointment"]

    var body: some View {
        VStack(alignment: .leading, spacing: M3taTokens.Spacing.l) {
            if !crm.isBound {
                unboundPanel
            } else if let snap = crm.snapshot {
                if snap.fullyOffline { offlinePanel(snap) }
                summaryPanel(snap)
                rosterPanel(snap)
                followUpsPanel(snap)
                retentionPanel(snap)
                tasksPanel(snap)
                createPanel
            } else {
                DashboardPanel(title: "CRM", capsules: [(nil, .designed)],
                               sourceLine: "M3ta-CRM machine API · /api/v1/*") {
                    Text(crm.isRefreshing ? "Checking the CRM…" : "Not checked yet")
                        .font(.callout).foregroundStyle(Color.dashMuted)
                }
            }
        }
        .onAppear { appeared = true }
        .onReceive(NotificationCenter.default.publisher(for: .consoleRefresh)) { _ in
            crm.config = CRMConfig.current()
            Task { await crm.refresh() }
        }
        .task(id: refreshSeconds) {
            while !Task.isCancelled {
                await crm.refresh()
                try? await Task.sleep(for: .seconds(max(5, refreshSeconds)))
            }
        }
    }

    // MARK: Unbound + offline faces

    private var unboundPanel: some View {
        DashboardPanel(title: "CRM not connected", capsules: [("API", .blocked)],
                       sourceLine: "M3ta-CRM machine API · no token in this app's environment") {
            VStack(alignment: .leading, spacing: M3taTokens.Spacing.s) {
                Text("This module is unbound. The Console never stores the CRM token, so it comes from the environment the app was launched with.")
                    .font(.callout).foregroundStyle(Color.dashText)
                if let problem = crm.config.bindProblem {
                    Text(problem).font(.callout).foregroundStyle(Color.dashSlot(.blocked))
                }
                Text("Set CRM_API_TOKEN to the same value the CRM server runs with, then relaunch the app (or press Refresh after changing the base URL). For the packaged app, launch it with the token in its environment (the run sheet's open --env step in the build notes); a Finder double-click inherits no shell environment. Base URL in use: \(crm.config.baseURL.absoluteString) (default http://localhost:3120; override with CRM_BASE_URL or Settings). The token is only ever sent to a loopback or HTTPS base URL. Writes attribute as x-agent-id: \(crm.config.agentId).")
                    .font(.caption).foregroundStyle(Color.dashMuted)
                Button("Reload config") { crm.config = CRMConfig.current(); Task { await crm.refresh() } }
                    .font(.caption)
            }
        }
    }

    private func offlinePanel(_ snap: CRMSnapshot) -> some View {
        DashboardPanel(title: "CRM not answering", capsules: [("API", .blocked)],
                       sourceLine: "Bound, but every read failed · checked \(snap.checkedAt.formatted(date: .omitted, time: .standard))") {
            VStack(alignment: .leading, spacing: 4) {
                if case .offline(let why) = snap.companies {
                    Text("Roster read: \(why)").font(.callout).foregroundStyle(Color.dashText)
                }
                Text("HTTP 503 means the CRM server's own token is unset (its lane is disabled). HTTP 401 means this app's token does not match the server's. A connection error means the server is not running at \(crm.config.baseURL.absoluteString). The panels below show each read's own state.")
                    .font(.caption).foregroundStyle(Color.dashMuted)
            }
        }
    }

    // MARK: Live panels

    private func cap<T>(_ p: Probe<T>) -> DashboardStatus { p.value != nil ? .live : .blocked }
    private func checked(_ snap: CRMSnapshot) -> String { "checked \(snap.checkedAt.formatted(date: .omitted, time: .standard))" }

    private func summaryPanel(_ snap: CRMSnapshot) -> some View {
        DashboardPanel(title: "Pipeline", capsules: [("Summary", cap(snap.summary))],
                       sourceLine: "GET /api/v1/summary · \(checked(snap))") {
            switch snap.summary {
            case .ok(let s):
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: M3taTokens.Spacing.l) {
                        metric("Open deals", "\(s.openDeals)")
                        metric("Pipeline", money(s.pipelineValue))
                        metric("Won", "\(s.wonDeals) · \(money(s.wonValue))")
                        metric("Lost", "\(s.lostDeals)")
                        metric("Contacts", "\(s.contacts)")
                        metric("Companies", "\(s.companies)")
                    }
                    if !s.byStage.isEmpty {
                        Text(s.byStage.keys.sorted().map { "\($0): \(s.byStage[$0]?.count ?? 0)" }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(Color.dashMuted)
                    }
                }
            case .offline(let why):
                Text("Summary unavailable (\(why))").font(.callout).foregroundStyle(Color.dashMuted)
            }
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.callout.weight(.semibold)).foregroundStyle(Color.dashText)
            Text(label).font(.caption).foregroundStyle(Color.dashMuted)
        }
    }

    private func money(_ v: Double) -> String { "$\(Int(v))" }

    private func rosterPanel(_ snap: CRMSnapshot) -> some View {
        DashboardPanel(title: "Roster", capsules: [("Companies", cap(snap.companies))],
                       sourceLine: "GET /api/v1/companies · identity is the slug · counts from the payload's _count") {
            switch snap.companies {
            case .ok(let rows):
                VStack(alignment: .leading, spacing: M3taTokens.Spacing.s) {
                    if rows.isEmpty { Text("The roster is empty.").font(.callout).foregroundStyle(Color.dashMuted) }
                    ForEach(rows) { c in
                        HStack(alignment: .firstTextBaseline, spacing: M3taTokens.Spacing.s) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.name).font(.callout.weight(.medium)).foregroundStyle(Color.dashText)
                                Text("\(c.slug) · \(c.type ?? "unknown type") · \(c.status ?? "unknown status")")
                                    .font(.caption).foregroundStyle(Color.dashMuted)
                            }
                            Spacer()
                            if let n = c.counts {
                                Text(countLine(n)).font(.caption.monospaced()).foregroundStyle(Color.dashMuted)
                            } else {
                                Text("counts not in payload").font(.caption).foregroundStyle(Color.dashMuted)
                            }
                        }
                    }
                }
            case .offline(let why):
                Text("Roster unavailable (\(why))").font(.callout).foregroundStyle(Color.dashMuted)
            }
        }
    }

    private func countLine(_ n: CRMCompany.Counts) -> String {
        func f(_ label: String, _ v: Int?) -> String? { v.map { "\(label) \($0)" } }
        return [f("contacts", n.contacts), f("deals", n.deals), f("tasks", n.tasks), f("snapshots", n.snapshots)]
            .compactMap { $0 }.joined(separator: " · ")
    }

    private func followUpsPanel(_ snap: CRMSnapshot) -> some View {
        DashboardPanel(title: "Follow-ups due", capsules: [("Due", cap(snap.followUps))],
                       sourceLine: "GET /api/v1/followups · open follow_up + retention tasks due now, oldest first") {
            switch snap.followUps {
            case .ok(let rows):
                taskRows(rows, empty: "Nothing due.")
            case .offline(let why):
                Text("Follow-ups unavailable (\(why))").font(.callout).foregroundStyle(Color.dashMuted)
            }
        }
    }

    private func tasksPanel(_ snap: CRMSnapshot) -> some View {
        DashboardPanel(title: "Open tasks", capsules: [("Tasks", cap(snap.tasks))],
                       sourceLine: "GET /api/v1/tasks · every open task") {
            switch snap.tasks {
            case .ok(let rows):
                taskRows(rows, empty: "No open tasks.")
            case .offline(let why):
                Text("Tasks unavailable (\(why))").font(.callout).foregroundStyle(Color.dashMuted)
            }
        }
    }

    private func taskRows(_ rows: [CRMTask], empty: String) -> some View {
        VStack(alignment: .leading, spacing: M3taTokens.Spacing.s) {
            if rows.isEmpty { Text(empty).font(.callout).foregroundStyle(Color.dashMuted) }
            ForEach(rows) { t in
                HStack(alignment: .firstTextBaseline, spacing: M3taTokens.Spacing.s) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t.title).font(.callout.weight(.medium)).foregroundStyle(Color.dashText)
                        Text(taskSubline(t)).font(.caption).foregroundStyle(Color.dashMuted)
                    }
                    Spacer()
                    if let d = t.dueDate {
                        Text(d.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption.monospaced())
                            .foregroundStyle(t.isOverdue() ? Color.dashSlot(.blocked) : Color.dashMuted)
                    } else {
                        Text("no due date").font(.caption).foregroundStyle(Color.dashMuted)
                    }
                }
            }
        }
    }

    private func taskSubline(_ t: CRMTask) -> String {
        var parts: [String] = [t.kind ?? "general"]
        if let c = t.contact?.fullName { parts.append(c) }
        if let c = t.company?.name { parts.append(c) }
        if let a = t.assignee?.name { parts.append("assignee \(a)") }
        return parts.joined(separator: " · ")
    }

    private func retentionPanel(_ snap: CRMSnapshot) -> some View {
        DashboardPanel(title: "Retention alerts", capsules: [("Cold", cap(snap.retention))],
                       sourceLine: "GET /api/v1/retention · window and cutoff come from the payload") {
            switch snap.retention {
            case .ok(let r):
                VStack(alignment: .leading, spacing: M3taTokens.Spacing.s) {
                    Text("Window: \(r.days) days · cutoff \(r.cutoff)")
                        .font(.caption).foregroundStyle(Color.dashMuted)
                    if r.cold.isEmpty { Text("Nobody is cold in this window.").font(.callout).foregroundStyle(Color.dashMuted) }
                    ForEach(r.cold) { c in
                        HStack(alignment: .firstTextBaseline, spacing: M3taTokens.Spacing.s) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.fullName).font(.callout.weight(.medium)).foregroundStyle(Color.dashText)
                                if let co = c.companyDisplayName { Text(co).font(.caption).foregroundStyle(Color.dashMuted) }
                            }
                            Spacer()
                            Text("last activity \(c.lastActivity ?? "unknown")")
                                .font(.caption).foregroundStyle(Color.dashMuted)
                        }
                    }
                }
            case .offline(let why):
                Text("Retention unavailable (\(why))").font(.callout).foregroundStyle(Color.dashMuted)
            }
        }
    }

    // MARK: Create forms (the HITL writes)

    private var createPanel: some View {
        DashboardPanel(title: "Add", capsules: [("Writes", .live)],
                       sourceLine: "POST /api/v1/contacts · POST /api/v1/tasks · your tap is the confirmation; writes attribute as \(crm.config.agentId)") {
            VStack(alignment: .leading, spacing: M3taTokens.Spacing.m) {
                HStack(spacing: M3taTokens.Spacing.s) {
                    TextField("Contact full name", text: $contactName)
                    TextField("Email", text: $contactEmail)
                    TextField("Phone", text: $contactPhone)
                    TextField("Company", text: $contactCompany)
                    Button("Create contact") {
                        writing = true
                        Task { await crm.createContact(CRMNewContact(
                            fullName: contactName,
                            email: contactEmail.isEmpty ? nil : contactEmail,
                            phone: contactPhone.isEmpty ? nil : contactPhone,
                            companyName: contactCompany.isEmpty ? nil : contactCompany)); writing = false }
                    }.disabled(writing || contactName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                HStack(spacing: M3taTokens.Spacing.s) {
                    TextField("Task title", text: $taskTitle)
                    Picker("Kind", selection: $taskKind) {
                        ForEach(taskKinds, id: \.self) { Text($0).tag($0) }
                    }.labelsHidden().frame(width: 130)
                    Toggle("Due", isOn: $taskHasDue).toggleStyle(.checkbox)
                    if taskHasDue { DatePicker("", selection: $taskDue, displayedComponents: [.date]).labelsHidden() }
                    Button("Create task") {
                        writing = true
                        Task { await crm.createTask(CRMNewTask(
                            title: taskTitle, kind: taskKind,
                            dueAt: taskHasDue ? taskDue : nil)); writing = false }
                    }.disabled(writing || taskTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Text("The server does not dedupe creates: a second confirmed tap makes a second row. The buttons disable while a write is in flight.")
                    .font(.caption).foregroundStyle(Color.dashMuted)
                if let w = crm.lastWrite {
                    switch w {
                    case .ok(let msg): Text(msg).font(.caption).foregroundStyle(Color.dashSlot(.live))
                    case .offline(let why): Text("Write failed: \(why)").font(.caption).foregroundStyle(Color.dashSlot(.blocked))
                    }
                }
            }
        }
    }
}

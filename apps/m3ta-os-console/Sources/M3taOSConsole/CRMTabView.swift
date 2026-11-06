import SwiftUI
import ConsoleCore

/// CRM tab (spec: specs/m3ta-os-console-crm.md): the native face of
/// M3ta-CRM inside the dashboard. Reads ride the tab's own refresh
/// loop (the dashboard's on-open probe set for the other tabs is
/// unchanged); the tab renders exactly three faces and no fourth:
/// unbound (no token in the environment), offline (bound, nothing
/// answered), and live (each panel its own Probe). Writes happen only
/// from the two create forms, on the operator's confirm tap.
///
/// Layout follows the dashboard's house grammar (the sibling tabs and
/// DashboardPanel): panels stack at Spacing.l; the Pipeline panel is
/// the hero strip (hero-scale metrics over caption labels, the
/// approvals-strip pattern); list rows are firstTextBaseline HStacks
/// with a medium callout name, a muted caption subline, and a
/// monospaced right value; sections inside a panel break on a
/// dashLine divider; forms compose as labeled sub-blocks on the
/// nested chip surface (the social-hero pattern).
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
            VStack(alignment: .leading, spacing: M3taTokens.Spacing.m) {
                VStack(alignment: .leading, spacing: M3taTokens.Spacing.s) {
                    Text("This module is unbound. The Console never stores the CRM token, so it comes from the environment the app was launched with.")
                        .font(.callout.weight(.medium)).foregroundStyle(Color.dashText)
                    if let problem = crm.config.bindProblem {
                        Text(problem).font(.callout).foregroundStyle(Color.dashSlot(.blocked))
                    }
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
            VStack(alignment: .leading, spacing: M3taTokens.Spacing.s) {
                if case .offline(let why) = snap.companies {
                    Text("Roster read: \(why)").font(.callout.weight(.medium)).foregroundStyle(Color.dashText)
                }
                Text("HTTP 503 means the CRM server's own token is unset (its lane is disabled). HTTP 401 means this app's token does not match the server's. A connection error means the server is not running at \(crm.config.baseURL.absoluteString). The panels below show each read's own state.")
                    .font(.caption).foregroundStyle(Color.dashMuted)
            }
        }
    }

    // MARK: Live panels

    private func cap<T>(_ p: Probe<T>) -> DashboardStatus { p.value != nil ? .live : .blocked }
    private func checked(_ snap: CRMSnapshot) -> String { "checked \(snap.checkedAt.formatted(date: .omitted, time: .standard))" }

    /// The hero strip: pipeline value, open deals, and won lead at the
    /// approvals-strip scale (rounded semibold value over a caption
    /// label); the remaining totals sit under a divider at reading
    /// scale; the stage breakdown closes the panel as revenue-style
    /// rows (name left, count and value monospaced in accent2 right).
    private func summaryPanel(_ snap: CRMSnapshot) -> some View {
        DashboardPanel(title: "Pipeline", capsules: [("Summary", cap(snap.summary))],
                       sourceLine: "GET /api/v1/summary · \(checked(snap))") {
            switch snap.summary {
            case .ok(let s):
                VStack(alignment: .leading, spacing: M3taTokens.Spacing.m) {
                    HStack(alignment: .top, spacing: M3taTokens.Spacing.xl) {
                        heroMetric("Pipeline", money(s.pipelineValue))
                        heroMetric("Open deals", "\(s.openDeals)")
                        heroMetric("Won", "\(s.wonDeals) · \(money(s.wonValue))")
                        Spacer(minLength: 0)
                    }
                    Divider().overlay(Color.dashLine)
                    HStack(spacing: M3taTokens.Spacing.l) {
                        metric("Lost", "\(s.lostDeals)")
                        metric("Contacts", "\(s.contacts)")
                        metric("Companies", "\(s.companies)")
                    }
                    if !s.byStage.isEmpty {
                        Divider().overlay(Color.dashLine)
                        VStack(alignment: .leading, spacing: M3taTokens.Spacing.s) {
                            ForEach(Array(s.byStage.keys.sorted().enumerated()), id: \.offset) { _, stage in
                                if let r = s.byStage[stage] {
                                    HStack(alignment: .firstTextBaseline) {
                                        Text(stage).font(.callout).foregroundStyle(Color.dashText)
                                        Spacer()
                                        Text("\(r.count) · \(money(r.value))")
                                            .font(.callout.monospaced().weight(.semibold)).foregroundStyle(Color.dashAccent2)
                                    }
                                }
                            }
                        }
                    }
                }
            case .offline(let why):
                Text("Summary unavailable (\(why))").font(.callout).foregroundStyle(Color.dashMuted)
            }
        }
    }

    private func heroMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(.title, design: .rounded).weight(.semibold)).monospacedDigit().foregroundStyle(Color.dashText)
            Text(label).font(.caption).foregroundStyle(Color.dashMuted)
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.callout.weight(.semibold)).foregroundStyle(Color.dashText)
            Text(label).font(.caption).foregroundStyle(Color.dashMuted)
        }
    }

    private func money(_ v: Double) -> String { v.formatted(.currency(code: "USD")) }

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
                                HStack(spacing: 6) {
                                    Text(c.name).font(.callout.weight(.medium)).foregroundStyle(Color.dashText)
                                    if let st = c.status {
                                        DashboardCapsule(label: nil, status: .raw(st))
                                    }
                                }
                                Text("\(c.slug) · \(c.type ?? "unknown type")")
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

    /// One task row shape for both task panels (the routes return the
    /// same row). Urgency reads off the existing slots, never new
    /// colors: a non-default priority renders as a muted raw capsule
    /// next to the title (the SurfaceRow pattern; the schema default
    /// "normal" renders nothing, so the capsule only appears where a
    /// priority was actually set), and an overdue due date takes the
    /// blocked slot. Row order is the server's; the view never
    /// re-sorts.
    private func taskRows(_ rows: [CRMTask], empty: String) -> some View {
        VStack(alignment: .leading, spacing: M3taTokens.Spacing.s) {
            if rows.isEmpty { Text(empty).font(.callout).foregroundStyle(Color.dashMuted) }
            ForEach(rows) { t in
                HStack(alignment: .firstTextBaseline, spacing: M3taTokens.Spacing.s) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(t.title).font(.callout.weight(.medium)).foregroundStyle(Color.dashText)
                            if let p = t.priority, p != "normal" {
                                Text(p)
                                    .font(.caption.monospaced().weight(.medium))
                                    .padding(.horizontal, 7).padding(.vertical, 2)
                                    .background(Color.dashSlot(.raw(p)).opacity(0.18), in: .capsule)
                                    .foregroundStyle(Color.dashSlot(.raw(p)))
                            }
                        }
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
                            Text("last activity \(lastActivityLine(c))")
                                .font(.caption.monospaced())
                                .foregroundStyle(Color.dashSlot(.designed))
                        }
                    }
                }
            case .offline(let why):
                Text("Retention unavailable (\(why))").font(.callout).foregroundStyle(Color.dashMuted)
            }
        }
    }

    /// Last activity as a readable date when the payload's ISO string
    /// parses (the CRMDate parser), the raw string when it does not:
    /// a display fallback, never a dropped value. The alert slot marks
    /// every row in this panel as cold by the server's own window.
    private func lastActivityLine(_ c: CRMContact) -> String {
        guard let raw = c.lastActivity else { return "unknown" }
        if let d = CRMDate.parse(raw) { return d.formatted(date: .abbreviated, time: .omitted) }
        return raw
    }

    // MARK: Create forms (the HITL writes)

    /// The two forms compose as labeled sub-blocks on the nested chip
    /// surface (the social-hero pattern), fields in the knowledge
    /// panel's rounded-border style. The write semantics are the
    /// spec's: confirm tap only, controls disabled while a write is
    /// in flight, the server's answer rendered under the divider.
    private var createPanel: some View {
        DashboardPanel(title: "Add", capsules: [("Writes", .live)],
                       sourceLine: "POST /api/v1/contacts · POST /api/v1/tasks · your tap is the confirmation; writes attribute as \(crm.config.agentId)") {
            VStack(alignment: .leading, spacing: M3taTokens.Spacing.m) {
                formBlock("New contact") {
                    HStack(spacing: M3taTokens.Spacing.s) {
                        TextField("Contact full name", text: $contactName).textFieldStyle(.roundedBorder)
                        TextField("Email", text: $contactEmail).textFieldStyle(.roundedBorder)
                    }
                    HStack(spacing: M3taTokens.Spacing.s) {
                        TextField("Phone", text: $contactPhone).textFieldStyle(.roundedBorder)
                        TextField("Company", text: $contactCompany).textFieldStyle(.roundedBorder)
                        Spacer()
                        Button("Create contact") {
                            writing = true
                            Task { await crm.createContact(CRMNewContact(
                                fullName: contactName,
                                email: contactEmail.isEmpty ? nil : contactEmail,
                                phone: contactPhone.isEmpty ? nil : contactPhone,
                                companyName: contactCompany.isEmpty ? nil : contactCompany)); writing = false }
                        }.disabled(writing || contactName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                formBlock("New task") {
                    HStack(spacing: M3taTokens.Spacing.s) {
                        TextField("Task title", text: $taskTitle).textFieldStyle(.roundedBorder)
                        Picker("Kind", selection: $taskKind) {
                            ForEach(taskKinds, id: \.self) { Text($0).tag($0) }
                        }.labelsHidden().frame(width: 130)
                    }
                    HStack(spacing: M3taTokens.Spacing.s) {
                        Toggle("Due", isOn: $taskHasDue).toggleStyle(.checkbox)
                        if taskHasDue { DatePicker("", selection: $taskDue, displayedComponents: [.date]).labelsHidden() }
                        Spacer()
                        Button("Create task") {
                            writing = true
                            Task { await crm.createTask(CRMNewTask(
                                title: taskTitle, kind: taskKind,
                                dueAt: taskHasDue ? taskDue : nil)); writing = false }
                        }.disabled(writing || taskTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                Divider().overlay(Color.dashLine)
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

    /// One labeled form sub-block: a semibold header over the fields,
    /// on the nested surface the dashboard uses for composed blocks.
    private func formBlock<Content: View>(_ title: String, @ViewBuilder fields: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: M3taTokens.Spacing.s) {
            Text(title).font(.callout.weight(.semibold)).foregroundStyle(Color.dashText)
            fields()
        }
        .padding(M3taTokens.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.dashBg.opacity(0.5), in: .rect(cornerRadius: M3taTokens.Radius.chip))
    }
}

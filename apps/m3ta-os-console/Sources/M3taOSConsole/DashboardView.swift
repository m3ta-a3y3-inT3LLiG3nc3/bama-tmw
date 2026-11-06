import SwiftUI
import AppKit
import ConsoleCore

/// The M3ta Way dashboard (spec: docs/designs/m3ta-way-dashboard-2026-11-02.md
/// plus the navigation and features addenda). A reading and routing
/// surface: it renders the DashboardState snapshot plus the Console's
/// existing loopback probe set, and collects nothing external on open.
/// Panels route (INTERNAL / LAUNCH / WEB per addendum 1); they never
/// duplicate another surface's data, and no control is a dead click.
struct DashboardView: View {
    @Environment(DashboardStore.self) private var dash
    @Environment(ChatRunStore.self) private var chat
    @AppStorage("jarvisRefreshSeconds") private var refreshSeconds = 10
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    let navigate: (Screen) -> Void

    @State private var tab: DashboardTab = .qb
    @State private var status: JarvisStatus?
    @State private var brain: BrainClient.StatusOutcome?
    @State private var copilotHealth: CopilotHealth.Result?
    @State private var appeared = false
    @State private var detailWidth: CGFloat = 960
    @State private var knowledgeQuery = ""

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider().overlay(Color.dashLine)
            ScrollView {
                Group {
                    switch tab {
                    case .qb: qbTab
                    case .hermes: HermesTabView(health: copilotHealth, runtimeUp: status?.runtimeUp ?? false, navigate: navigate, goToApprovals: { tab = .qb })
                    case .metaOS: MetaOSTabView(status: status, navigate: navigate)
                    case .adam: ADAMTabView()
                    case .crm: CRMTabView()
                    }
                }
                .padding(M3taTokens.Spacing.xl)
                .onGeometryChange(for: CGFloat.self, of: { proxy in proxy.size.width }, action: { detailWidth = $0 })
            }
        }
        .background(Color.dashBg)
        .onAppear { if !appeared { appeared = true } }
        .onReceive(NotificationCenter.default.publisher(for: .consoleRefresh)) { _ in Task { await probe() } }
        .task(id: refreshSeconds) {
            while !Task.isCancelled {
                await probe()
                try? await Task.sleep(for: .seconds(max(5, refreshSeconds)))
            }
        }
    }

    /// The allowed on-open read set, named exactly (spec Definition of
    /// done 2): the three Overview probes plus the JarvisClient reads
    /// and the rea-mcp health probe JarvisLiveView already makes. Each
    /// renders with its checked-at time.
    func probe() async {
        async let s = JarvisClient.status()
        async let b = BrainClient.status()
        async let c = CopilotHealth.check()
        status = await s; brain = await b; copilotHealth = await c
    }

    // MARK: Tab bar (features addendum section 1)

    private var tabBar: some View {
        HStack(spacing: M3taTokens.Spacing.s) {
            ForEach(DashboardTab.allCases) { t in
                Button { tab = t } label: {
                    VStack(spacing: 3) {
                        Text(t.rawValue).font(.headline)
                            .foregroundStyle(tab == t ? Color.dashAccent : Color.dashMuted)
                        Rectangle().fill(tab == t ? Color.dashAccent : Color.clear).frame(height: 2)
                    }
                    .padding(.horizontal, M3taTokens.Spacing.s)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(t.rawValue) tab")
                .accessibilityAddTraits(tab == t ? [.isSelected] : [])
            }
            Spacer()
            if let s = dash.state {
                Text(s.isStale() ? "Snapshot stale" : "Snapshot").font(.caption).foregroundStyle(s.isStale() ? Color.dashSlot(.designed) : Color.dashMuted)
            }
        }
        .padding(.horizontal, M3taTokens.Spacing.xl).padding(.top, M3taTokens.Spacing.s)
        .background(Color.dashBg)
    }

    // MARK: QB tab (the parent spec's seven panels, unchanged order)

    private var qbTab: some View {
        VStack(alignment: .leading, spacing: M3taTokens.Spacing.xl) {
            heroPanel.entrance(0, appeared: appeared, reduceMotion: reduceMotion)
            tickerStrip
            approvalsPanel.entrance(1, appeared: appeared, reduceMotion: reduceMotion)
            LazyVGrid(columns: gridColumns, alignment: .leading, spacing: M3taTokens.Spacing.l) {
                surfacesPanel.entrance(2, appeared: appeared, reduceMotion: reduceMotion)
                revenuePanel.entrance(3, appeared: appeared, reduceMotion: reduceMotion)
                socialPanel.entrance(4, appeared: appeared, reduceMotion: reduceMotion)
                skillsPanel.entrance(5, appeared: appeared, reduceMotion: reduceMotion)
                knowledgePanel.entrance(6, appeared: appeared, reduceMotion: reduceMotion)
            }
        }
    }

    private var gridColumns: [GridItem] {
        detailWidth < 720 ? [GridItem(.flexible())] : [GridItem(.flexible()), GridItem(.flexible())]
    }

    // MARK: Panel 1 + 2: hero brief with the voice presence fused in

    private var heroPanel: some View {
        DashboardPanel(title: "Today", capsules: [(nil, .snapshot)],
                       sourceLine: heroSourceLine) {
            HStack(alignment: .top, spacing: M3taTokens.Spacing.xl) {
                BrandBadgeImage()
                VStack(alignment: .leading, spacing: M3taTokens.Spacing.s) {
                    Text(greeting).font(.title2.bold()).foregroundStyle(Color.dashText)
                    if let s = dash.state {
                        let stale = s.isStale()
                        ForEach(Array(s.rankedBriefLines().enumerated()), id: \.offset) { _, line in
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(line.kind.rawValue).font(.caption.monospaced().weight(.semibold)).foregroundStyle(Color.dashAccent2)
                                Text((stale ? "As of \(shortDate(s.capturedAt)): " : "") + line.text)
                                    .font(.callout).foregroundStyle(Color.dashText)
                                Text("· \(line.sourceTag)").font(.caption).foregroundStyle(Color.dashMuted)
                            }
                        }
                        if s.rankedBriefLines().isEmpty { Text("No brief lines in this snapshot.").font(.callout).foregroundStyle(Color.dashMuted) }
                    } else {
                        Text("No snapshot loaded").font(.callout).foregroundStyle(Color.dashMuted)
                        if let e = dash.error { Text(e).font(.caption).foregroundStyle(Color.dashSlot(.blocked)) }
                    }
                }
                Spacer(minLength: 0)
                VoicePresenceView(runtimeUp: status?.runtimeUp ?? false) { navigate(.copilot) }
            }
        }
    }

    private var heroSourceLine: String {
        guard let s = dash.state else { return "DashboardState snapshot · none loaded" }
        return "Brief as of \(s.capturedAt) · \(s.source) · \(dash.sourcePath ?? "?")"
    }

    private var greeting: String {
        let f = DateFormatter(); f.dateStyle = .full; f.timeStyle = .none
        return f.string(from: Date())
    }

    private func shortDate(_ iso: String) -> String {
        guard let d = SnapshotAge.date(iso) else { return iso }
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .none
        return f.string(from: d)
    }

    // MARK: Ticker (features addendum section 2)

    @ViewBuilder private var tickerStrip: some View {
        if let s = dash.state, let items = s.tickerItems, !items.isEmpty {
            let segments = tickerSegments(state: s, items: items)
            if reduceMotion {
                // Reduce Motion replacement: a static, wrapped summary
                // block with the same items and the same date segment.
                Text(segments.map(\.text).joined(separator: "  ·  "))
                    .font(.caption).foregroundStyle(Color.dashMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, M3taTokens.Spacing.l).padding(.vertical, M3taTokens.Spacing.s)
                    .background(Color.dashSurface, in: .rect(cornerRadius: M3taTokens.Radius.chip))
                    .accessibilityLabel("System ticker, snapshot \(s.capturedAt)")
            } else {
                TickerView(segments: segments)
                    .frame(maxWidth: .infinity)
                    .background(Color.dashSurface, in: .rect(cornerRadius: M3taTokens.Radius.chip))
                    .accessibilityLabel("System ticker, snapshot \(s.capturedAt)")
            }
        }
    }

    /// The strip opens and closes with the snapshot date segment; the
    /// only live segment is the approvals count from the probe the app
    /// already makes, marked and labeled with its checked-at time. The
    /// word "live" never appears on the strip.
    private func tickerSegments(state s: DashboardState, items: [TickerItem]) -> [TickerView.Segment] {
        let dateSeg = "Snapshot \(shortDate(s.capturedAt))"
        var segs: [TickerView.Segment] = [.init(text: dateSeg, isLive: false)]
        if let st = status {
            let pending = st.rea.value?.pending.map(String.init) ?? "Unknown"
            let t = st.checkedAt.formatted(date: .omitted, time: .standard)
            segs.append(.init(text: "Approvals pending: \(pending) (checked \(t))", isLive: true))
        }
        segs += items.filter { !$0.text.hasPrefix("Approvals pending:") }
            .map { .init(text: "\($0.text) (\($0.sourceTag))", isLive: false) }
        segs.append(.init(text: dateSeg, isLive: false))
        return segs
    }

    // MARK: Panel 3: approvals strip

    private var approvalsPanel: some View {
        DashboardPanel(title: "Approvals", capsules: [("Count", .live), ("Queue detail", .blocked)],
                       sourceLine: "rea-mcp /health, pending · Jev pre-screens; M3ta resolves",
                       linkLabel: "Open Runtime status", linkAction: { navigate(.copilot) }) {
            HStack(alignment: .firstTextBaseline, spacing: M3taTokens.Spacing.l) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(status?.rea.value?.pending.map(String.init) ?? "Unknown")
                        .font(.system(.largeTitle, design: .rounded).weight(.semibold)).monospacedDigit().foregroundStyle(Color.dashText)
                    Text("pending approvals").font(.caption).foregroundStyle(Color.dashMuted)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(status.map { "Checked \($0.checkedAt.formatted(date: .omitted, time: .standard))" } ?? "Not checked yet")
                        .font(.callout).foregroundStyle(Color.dashText)
                    Text("Queue detail needs a JARVIS endpoint that lists pending items; the health probe exposes the count only.")
                        .font(.caption).foregroundStyle(Color.dashMuted)
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: Panel 4: command surfaces

    private var surfacesPanel: some View {
        DashboardPanel(title: "Command surfaces", capsules: [(nil, .snapshot)],
                       sourceLine: "Snapshot rows from DashboardState · JARVIS row from the loopback probes") {
            VStack(alignment: .leading, spacing: M3taTokens.Spacing.s) {
                jarvisLiveRow
                if let s = dash.state {
                    ForEach(Array(s.panel4OrderedSurfaces().enumerated()), id: \.offset) { _, r in
                        SurfaceRowView(row: r) { url in openURL(url) }
                    }
                } else {
                    Text("No snapshot loaded").font(.callout).foregroundStyle(Color.dashMuted)
                }
            }
        }
    }

    private var jarvisLiveRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: M3taTokens.Spacing.s) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("JARVIS").font(.callout.weight(.medium)).foregroundStyle(Color.dashText)
                    DashboardCapsule(label: nil, status: .live)
                }
                Text(jarvisLiveNote).font(.caption).foregroundStyle(Color.dashMuted)
            }
            Spacer()
            Button("Runtime status") { navigate(.copilot) }.buttonStyle(.link).font(.caption)
        }
    }

    private var jarvisLiveNote: String {
        guard let st = status else { return "Not checked yet" }
        let t = st.checkedAt.formatted(date: .omitted, time: .standard)
        if let m = st.models.value {
            return "Default route \(m.default.model) (\(m.default.paid ? "paid" : "local")) · paid models on: \(m.paidEnabledCount) · checked \(t)"
        }
        return st.runtimeUp ? "Runtime healthy; model route unread · checked \(t)" : "Runtime not answering · checked \(t)"
    }

    // MARK: Panel 5: revenue engine

    private var revenuePanel: some View {
        DashboardPanel(title: "Revenue engine", capsules: [(nil, .snapshot), ("Ledger", .blocked)],
                       sourceLine: "Confirmed terms carried in DashboardState · no other revenue number exists to display") {
            VStack(alignment: .leading, spacing: M3taTokens.Spacing.s) {
                if let r = dash.state?.revenue {
                    ForEach(Array(r.ladder.enumerated()), id: \.offset) { _, row in
                        HStack(alignment: .firstTextBaseline) {
                            Text(row.name).font(.callout).foregroundStyle(Color.dashText)
                            Spacer()
                            Text(row.price).font(.callout.monospaced().weight(.semibold)).foregroundStyle(Color.dashAccent2)
                            if let g = row.gateNote { Text(g).font(.caption).foregroundStyle(Color.dashMuted) }
                        }
                    }
                    if let line = r.verifiedRevenueLine {
                        Text("Verified revenue to date: \(line) (empire audit, \(r.verifiedRevenueAsOf ?? "date unknown")).")
                            .font(.callout.weight(.medium)).foregroundStyle(Color.dashText)
                    }
                    if let g = r.gateNote { Text(g).font(.caption).foregroundStyle(Color.dashMuted) }
                } else {
                    Text("No revenue state in this snapshot.").font(.callout).foregroundStyle(Color.dashMuted)
                }
                HStack(spacing: 6) {
                    DashboardCapsule(label: "Commission ledger", status: .blocked)
                    Text("Not built (G7). Per-offer money appears here when it exists.").font(.caption).foregroundStyle(Color.dashMuted)
                }
            }
        }
    }

    // MARK: Social panel (features addendum section 3)

    private var socialPanel: some View {
        DashboardPanel(title: "Social", capsules: socialCapsules,
                       sourceLine: "Producer reads via the platform connectors · panel renders the snapshot") {
            VStack(alignment: .leading, spacing: M3taTokens.Spacing.s) {
                if let social = dash.state?.social {
                    if let accounts = social.accounts, !accounts.isEmpty {
                        ForEach(Array(accounts.prefix(3).enumerated()), id: \.offset) { _, a in socialHero(a) }
                        ForEach(Array(accounts.enumerated()), id: \.offset) { _, a in socialMetricRows(a) }
                    }
                    if let activity = social.activity, !activity.isEmpty {
                        Divider().overlay(Color.dashLine)
                        ForEach(Array(activity.prefix(6).enumerated()), id: \.offset) { _, p in
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(p.platform).font(.caption.weight(.semibold)).foregroundStyle(Color.dashAccent2)
                                Text(p.text).font(.caption).foregroundStyle(Color.dashText).lineLimit(1)
                                Spacer()
                                Text(p.stateWord).font(.caption.monospaced()).foregroundStyle(Color.dashMuted)
                            }
                        }
                    }
                    if (social.accounts ?? []).isEmpty && (social.activity ?? []).isEmpty {
                        Text("Social snapshot carries no accounts or activity yet.").font(.callout).foregroundStyle(Color.dashMuted)
                    }
                } else {
                    Text("No social snapshot yet. Producer routes: Instagram, Facebook, Threads (connected). TikTok analytics: blocked, no route exists. Postiz scheduled posts: blocked until the API key and Channels land.")
                        .font(.callout).foregroundStyle(Color.dashMuted)
                }
                Text("This panel displays and routes; it never publishes. Auto-post stays under the phased ruling (2026-11-02).")
                    .font(.caption).foregroundStyle(Color.dashMuted)
            }
        }
    }

    private var socialCapsules: [(String?, DashboardStatus)] {
        dash.state?.social == nil ? [("Accounts", .designed), ("TikTok", .blocked), ("Postiz", .blocked)]
                                  : [("Accounts", .snapshot), ("TikTok", .blocked), ("Postiz", .blocked)]
    }

    private func socialHero(_ a: SocialAccount) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(a.handle).font(.callout.weight(.semibold)).foregroundStyle(Color.dashText)
                Text(a.platform).font(.caption).foregroundStyle(Color.dashMuted)
                Spacer()
                if let f = a.followers {
                    Text("\(f) followers").font(.callout.monospaced()).foregroundStyle(Color.dashText)
                    Text("as of \(a.followersAsOf ?? "unknown")").font(.caption).foregroundStyle(Color.dashMuted)
                } else {
                    Text("Followers: Unknown").font(.caption).foregroundStyle(Color.dashMuted)
                }
            }
            if let w = a.windowLabel { Text(w).font(.caption).foregroundStyle(Color.dashMuted) }
        }
        .padding(M3taTokens.Spacing.s)
        .background(Color.dashBg.opacity(0.5), in: .rect(cornerRadius: M3taTokens.Radius.chip))
    }

    @ViewBuilder private func socialMetricRows(_ a: SocialAccount) -> some View {
        if let metrics = a.metrics, !metrics.isEmpty {
            ForEach(Array(metrics.enumerated()), id: \.offset) { _, m in
                HStack {
                    Text("\(a.platform) · \(m.name)").font(.caption).foregroundStyle(Color.dashMuted)
                    Spacer()
                    Text(m.value).font(.caption.monospaced()).foregroundStyle(Color.dashText)
                    Text(m.asOf).font(.caption).foregroundStyle(Color.dashMuted)
                }
            }
        }
    }

    // MARK: Panel 6: Skills Brain

    private var skillsPanel: some View {
        DashboardPanel(title: "Skills Brain", capsules: [("REA skills", .live), ("Registry", .blocked)],
                       sourceLine: "Two sources, two states · JARVIS REA skills are not the Skills Brain registry",
                       linkLabel: "Open Runtime status", linkAction: { navigate(.copilot) }) {
            VStack(alignment: .leading, spacing: M3taTokens.Spacing.s) {
                if let k = status?.skills.value {
                    Text("Tools exposed: \(k.tools.count)").font(.callout.weight(.medium)).foregroundStyle(Color.dashText)
                    Text(k.tools.prefix(12).map(\.name).joined(separator: ", ") + (k.tools.count > 12 ? " …" : ""))
                        .font(.caption).foregroundStyle(Color.dashMuted)
                } else {
                    Text("REA skills: Unknown (probe has not answered)").font(.callout).foregroundStyle(Color.dashMuted)
                }
                Divider().overlay(Color.dashLine)
                Text(dash.state?.skillsBrain?.blockerLine ?? "Registry state not in this snapshot.")
                    .font(.callout).foregroundStyle(Color.dashText)
                Text("Registry will hold: skill name, owner surface, version, where it is wired (designed schema).")
                    .font(.caption).foregroundStyle(Color.dashMuted)
            }
        }
    }

    // MARK: Panel 7: knowledge brain

    private var knowledgePanel: some View {
        DashboardPanel(title: "Knowledge brain", capsules: [("Brain status", .live), ("Corpus", .snapshot)],
                       sourceLine: "Brain status from rea-mcp · corpus state from DashboardState · the Console adds no Notion feed") {
            VStack(alignment: .leading, spacing: M3taTokens.Spacing.s) {
                switch brain {
                case .online(let m):
                    Text(m.keys.sorted().map { "\($0.capitalized): \(m[$0] ?? "unknown")" }.joined(separator: " · "))
                        .font(.callout).foregroundStyle(Color.dashText)
                case .offline(let why):
                    Text("Brain offline (\(why))").font(.callout).foregroundStyle(Color.dashSlot(.blocked))
                case .none:
                    Text("Brain status: checking…").font(.callout).foregroundStyle(Color.dashMuted)
                }
                HStack(spacing: M3taTokens.Spacing.s) {
                    TextField("Search the brain", text: $knowledgeQuery)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { routeBrainSearch() }
                    Button("Search in Brain") { routeBrainSearch() }.disabled(knowledgeQuery.isEmpty)
                }
                if let k = dash.state?.knowledge {
                    ForEach(Array(k.corpus.enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(item.name).font(.callout).foregroundStyle(Color.dashText)
                            DashboardCapsule(label: nil, status: item.status)
                            if let n = item.note { Text(n).font(.caption).foregroundStyle(Color.dashMuted) }
                            Spacer()
                        }
                    }
                    if let q = k.queueCounts {
                        Text("Ingest queue: \(q.waiting) waiting · \(q.inPipeline) in pipeline · \(q.failed) failed (as of \(q.asOf))")
                            .font(.caption).foregroundStyle(Color.dashMuted)
                    }
                }
            }
        }
    }

    /// INTERNAL route: hand the query to the Brain screen, which picks it
    /// up on appearance. The dashboard grows no second search.
    private func routeBrainSearch() {
        let q = knowledgeQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        UserDefaults.standard.set(q, forKey: "brainPendingQuery")
        navigate(.brain)
    }
}

/// The dashboard tabs (features addendum section 1; CRM added by the
/// CRM module spec, specs/m3ta-os-console-crm.md). QB is the
/// orchestration home and the default on launch.
enum DashboardTab: String, CaseIterable, Identifiable {
    case qb = "QB", hermes = "Hermes", metaOS = "Meta OS", adam = "A.D.A.M.", crm = "CRM"
    var id: String { rawValue }
}

/// Entrance motion (spec motion item 1): panels rise and fade in a 60ms
/// stagger, once per appearance, never on refresh; Reduce Motion renders
/// end states with no transition.
private struct EntranceModifier: ViewModifier {
    let index: Int
    let appeared: Bool
    let reduceMotion: Bool
    func body(content: Content) -> some View {
        content
            .opacity(appeared || reduceMotion ? 1 : 0)
            .offset(y: appeared || reduceMotion ? 0 : 8)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.35).delay(Double(index) * 0.06), value: appeared)
    }
}

private extension View {
    func entrance(_ index: Int, appeared: Bool, reduceMotion: Bool) -> some View {
        modifier(EntranceModifier(index: index, appeared: appeared, reduceMotion: reduceMotion))
    }
}

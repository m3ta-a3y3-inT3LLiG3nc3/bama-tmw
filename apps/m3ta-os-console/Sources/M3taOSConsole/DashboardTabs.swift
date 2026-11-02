import SwiftUI
import AppKit
import ConsoleCore

/// The ratified Th3 M3ta Way badge from Resources/brand (the brand kit's
/// own 1080px PNG export; the SVG master sits alongside it as the source
/// record, per the spec's asset path). Falls back to the drawn mark when
/// the asset is not in the bundle (dev runs via `swift run`).
struct BrandBadgeImage: View {
    var size: CGFloat = 72
    var body: some View {
        ZStack {
            // The hero's single glow allowance (tokens rule: one glow per
            // surface), behind the badge only.
            Circle().fill(Color.dashGlow.opacity(0.30)).blur(radius: 18).frame(width: size * 1.5, height: size * 1.5)
            if let img = Self.badge {
                Image(nsImage: img).resizable().scaledToFit().frame(width: size, height: size)
                    .accessibilityLabel("Th3 M3ta Way badge")
            } else {
                RoundedRectangle(cornerRadius: 8).fill(Color.dashSurface).frame(width: size, height: size)
                    .overlay(Image(systemName: "cube.transparent").font(.title).foregroundStyle(Color.dashAccent))
                    .accessibilityLabel("Th3 M3ta Way badge (placeholder, asset not bundled)")
            }
        }
    }
    static let badge: NSImage? = {
        guard let url = Bundle.main.url(forResource: "th3-m3ta-way-badge-circle-1080px", withExtension: "png", subdirectory: "brand") else { return nil }
        return NSImage(contentsOf: url)
    }()
}

/// Panel 2's presence orb, shared by the QB hero and the Hermes tab (the
/// same component reading the same state, per the addendum). States map
/// one to one to real run states: working (a chat run is streaming),
/// idle (runtime reachable), offline. There is no listening state (no
/// microphone) and no speaking state (no speech output); the copy says
/// so on its face. The orb animates only in `working`, driven by the
/// run state, so the motion is evidence, not decoration.
struct VoicePresenceView: View {
    @Environment(ChatRunStore.self) private var chat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let runtimeUp: Bool
    let onOpenChat: () -> Void

    private enum Presence { case working, idle, offline }
    private var presence: Presence {
        if chat.acc.isRunning { return .working }
        return runtimeUp ? .idle : .offline
    }

    var body: some View {
        VStack(spacing: M3taTokens.Spacing.s) {
            Circle()
                .fill(orbColor)
                .frame(width: 44, height: 44)
                .scaleEffect(presence == .working && !reduceMotion ? 1.12 : 1.0)
                .animation(presence == .working && !reduceMotion
                           ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true) : nil,
                           value: presence == .working)
                .accessibilityHidden(true)
            Text(presenceWord).font(.caption.weight(.semibold)).foregroundStyle(Color.dashText)
            Text("Voice: text chat live. Speech in and out: designed, not wired.")
                .font(.caption).foregroundStyle(Color.dashMuted)
                .multilineTextAlignment(.center).frame(maxWidth: 190)
            Button("Open Copilot") { onOpenChat() }.buttonStyle(.link).font(.caption)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Voice presence: \(presenceWord). Text chat live; speech designed, not wired.")
    }

    private var orbColor: Color {
        switch presence {
        case .working: return Color.dashAccent
        case .idle: return Color.dashSlot(.live)
        case .offline: return Color.dashMuted.opacity(0.5)
        }
    }
    private var presenceWord: String {
        switch presence {
        case .working: return "Working"
        case .idle: return "Idle"
        case .offline: return "Offline"
        }
    }
}

/// The hero ticker (features addendum section 2, motion item 5): one
/// linear scroll loop, constant speed, no bounce. It pauses on hover or
/// keyboard focus. Data arrives as segments; nothing is collected here.
struct TickerView: View {
    struct Segment: Equatable { let text: String; let isLive: Bool }
    let segments: [Segment]
    @State private var width: CGFloat = 0
    @State private var start = Date()
    @State private var pauseBegan: Date? = nil
    @State private var pausedTotal: TimeInterval = 0
    @State private var hovering = false
    @FocusState private var focused: Bool
    private let speed: Double = 45 // points per second

    var body: some View {
        TimelineView(.animation) { ctx in
            let x = offset(at: ctx.date)
            HStack(spacing: 0) { strip; strip }
                .offset(x: x)
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipped()
        }
        .frame(height: 26)
        .focusable()
        .focused($focused)
        .onHover { h in
            hovering = h
            if h { pauseBegan = Date() }
            else if let p = pauseBegan { pausedTotal += Date().timeIntervalSince(p); pauseBegan = nil }
        }
        .onChange(of: focused) { _, f in
            if f { pauseBegan = Date() }
            else if let p = pauseBegan { pausedTotal += Date().timeIntervalSince(p); pauseBegan = nil }
        }
        .onPreferenceChange(TickerWidthKey.self) { width = $0 }
    }

    private func offset(at now: Date) -> CGFloat {
        guard width > 0 else { return 0 }
        let end = pauseBegan ?? now
        let elapsed = max(0, end.timeIntervalSince(start) - pausedTotal)
        return -CGFloat((elapsed * speed).truncatingRemainder(dividingBy: Double(width)))
    }

    private var strip: some View {
        HStack(spacing: 24) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                Text(seg.text)
                    .font(.caption.monospaced())
                    .foregroundStyle(seg.isLive ? Color.dashSlot(.live) : Color.dashMuted)
                    .fixedSize()
            }
        }
        .padding(.vertical, 5)
        .padding(.trailing, 24)
        .background(GeometryReader { g in Color.clear.preference(key: TickerWidthKey.self, value: g.size.width) })
    }
}

private struct TickerWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// One snapshot row: name, capsule, note, count with its date, and the
/// row's route when the snapshot carries one (WEB, class (c)). Absent
/// routeURL means no link control renders (no dead clicks). The Otto
/// row additionally renders its LAUNCH action disabled, with the
/// blocker on its face, per addendum 1.
struct SurfaceRowView: View {
    let row: SurfaceRow
    var open: (URL) -> Void = { _ in }
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: M3taTokens.Spacing.s) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(row.name).font(.callout.weight(.medium)).foregroundStyle(Color.dashText)
                    DashboardCapsule(label: nil, status: row.status)
                    if let c = row.count {
                        Text("\(c)").font(.callout.monospaced().weight(.semibold)).foregroundStyle(Color.dashText)
                        Text("as of \(row.countAsOf ?? "unknown")").font(.caption).foregroundStyle(Color.dashMuted)
                    }
                }
                if let n = row.note { Text(n).font(.caption).foregroundStyle(Color.dashMuted).lineLimit(3) }
                if let a = row.asOf { Text("As of \(a)").font(.caption2).foregroundStyle(Color.dashMuted) }
            }
            Spacer()
            if row.name == "Otto" {
                Button("Launch in Otto") {}.disabled(true).font(.caption)
                    .help("Blocked on M3ta's in-app scoped grant in Otto")
            }
            if let raw = row.routeURL, let url = URL(string: raw) {
                Button("Open") { open(url) }.buttonStyle(.link).font(.caption)
            }
        }
    }
}

/// Hermes tab: the voice presence grown to a full tab, plus comms rows.
/// Hermes delivers approvals; the decision surface stays on the QB tab.
struct HermesTabView: View {
    @Environment(DashboardStore.self) private var dash
    let health: CopilotHealth.Result?
    let runtimeUp: Bool
    let navigate: (Screen) -> Void
    let goToApprovals: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: M3taTokens.Spacing.l) {
            DashboardPanel(title: "Voice presence", capsules: [("Presence", .live), ("Speech", .designed)],
                           sourceLine: "Shared ChatRunStore state · the same orb as the QB hero",
                           linkLabel: "Open Copilot chat", linkAction: { navigate(.copilot) }) {
                HStack { Spacer(); VoicePresenceView(runtimeUp: runtimeUp) { navigate(.copilot) }; Spacer() }
            }
            DashboardPanel(title: "Comms surfaces", capsules: [(nil, .snapshot)],
                           sourceLine: "From DashboardState only · none of these is a Console feed") {
                VStack(alignment: .leading, spacing: M3taTokens.Spacing.s) {
                    ForEach(Array((dash.state?.commsRows ?? []).enumerated()), id: \.offset) { _, r in SurfaceRowView(row: r) }
                    if (dash.state?.commsRows ?? []).isEmpty { Text("No comms rows in this snapshot.").font(.callout).foregroundStyle(Color.dashMuted) }
                }
            }
            DashboardPanel(title: "Approvals delivery", capsules: [(nil, .designed)],
                           sourceLine: "Hermes captures, clarifies, briefs, and delivers approvals; decisions happen on the QB tab",
                           linkLabel: "Go to the approvals strip (QB tab)", linkAction: goToApprovals) {
                Text("This tab links to the approvals strip; it does not duplicate it, and it never decides.")
                    .font(.callout).foregroundStyle(Color.dashText)
            }
        }
    }
}

/// Meta OS tab: the platform view. Runtime rows read the same loopback
/// probe set; everything else is the snapshot, labeled.
struct MetaOSTabView: View {
    @Environment(DashboardStore.self) private var dash
    @Environment(\.openURL) private var openURL
    let status: JarvisStatus?
    let navigate: (Screen) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: M3taTokens.Spacing.l) {
            DashboardPanel(title: "Runtimes", capsules: [(nil, .live)],
                           sourceLine: "Loopback probes the Console already makes · checked-at on each line",
                           linkLabel: "Open Runtime status", linkAction: { navigate(.copilot) }) {
                VStack(alignment: .leading, spacing: 4) {
                    runtimeLine("JARVIS runtime", ok: status?.runtimeUp ?? false)
                    runtimeLine("rea-mcp", ok: status?.reaUp ?? false)
                    if let m = status?.models.value {
                        Text("Default route \(m.default.model) (\(m.default.paid ? "paid" : "local")) · fallback \(m.fallback ?? "unknown") · paid models on: \(m.paidEnabledCount)")
                            .font(.caption).foregroundStyle(Color.dashMuted)
                    }
                    Text(status.map { "Checked \($0.checkedAt.formatted(date: .omitted, time: .standard))" } ?? "Not checked yet")
                        .font(.caption).foregroundStyle(Color.dashMuted)
                }
            }
            rowsPanel("M3ta-OS modules", rows: dash.state?.platformModules,
                      empty: "No module rows in this snapshot. Modules render \"Unknown\" until a record names their state.")
            rowsPanel("CopilotKit Intelligence projects", rows: dash.state?.intelligenceProjects,
                      empty: "No Intelligence project rows in this snapshot.")
            rowsPanel("Platform steps and stacks", rows: (dash.state?.platformRows ?? []) + (dash.state?.appRows ?? []),
                      empty: "No platform rows in this snapshot.")
        }
    }

    private func runtimeLine(_ name: String, ok: Bool) -> some View {
        HStack(spacing: 6) {
            Circle().fill(ok ? Color.dashSlot(.live) : Color.dashSlot(.blocked)).frame(width: 8, height: 8).accessibilityHidden(true)
            Text(name).font(.callout).foregroundStyle(Color.dashText)
            Text(ok ? "healthy" : "not answering").font(.caption).foregroundStyle(Color.dashMuted)
        }
    }

    private func rowsPanel(_ title: String, rows: [SurfaceRow]?, empty: String) -> some View {
        DashboardPanel(title: title, capsules: [(nil, .snapshot)], sourceLine: "From DashboardState only") {
            VStack(alignment: .leading, spacing: M3taTokens.Spacing.s) {
                ForEach(Array((rows ?? []).enumerated()), id: \.offset) { _, r in
                    SurfaceRowView(row: r) { url in openURL(url) }
                }
                if (rows ?? []).isEmpty { Text(empty).font(.callout).foregroundStyle(Color.dashMuted) }
            }
        }
    }
}

/// A.D.A.M. tab: the workforce view. The four A.D.A.M. autonomy levels
/// are the spine; the action-card L0-L4 are a separate vocabulary and
/// are never merged into these rows.
struct ADAMTabView: View {
    @Environment(DashboardStore.self) private var dash
    private let levels = ["Copilot", "Approval", "Supervised", "Autonomous"]
    var body: some View {
        VStack(alignment: .leading, spacing: M3taTokens.Spacing.l) {
            DashboardPanel(title: "Autonomy levels", capsules: [(nil, .snapshot)],
                           sourceLine: "A.D.A.M. levels per the ecosystem definition · the action-card L0-L4 stay a separate vocabulary") {
                HStack(spacing: M3taTokens.Spacing.s) {
                    ForEach(Array(levels.enumerated()), id: \.offset) { i, level in
                        Text("\(i + 1) · \(level)").font(.callout.weight(.medium)).foregroundStyle(Color.dashText)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Color.dashAccent.opacity(0.14), in: .capsule)
                    }
                    Spacer()
                }
            }
            DashboardPanel(title: "Workforce census", capsules: [(nil, .snapshot)],
                           sourceLine: "Census rows by home system, from DashboardState only, each with its count date") {
                VStack(alignment: .leading, spacing: M3taTokens.Spacing.s) {
                    ForEach(Array((dash.state?.workforceCensus ?? []).enumerated()), id: \.offset) { _, r in SurfaceRowView(row: r) }
                    if (dash.state?.workforceCensus ?? []).isEmpty { Text("No census rows in this snapshot.").font(.callout).foregroundStyle(Color.dashMuted) }
                }
            }
            DashboardPanel(title: "Per-agent detail", capsules: [(nil, .designed)],
                           sourceLine: "No Console feed lists agents from any of these systems today; this tab does not invent one") {
                Text("Census rows and routes out stand in for a roster until a real feed exists.")
                    .font(.callout).foregroundStyle(Color.dashText)
            }
        }
    }
}

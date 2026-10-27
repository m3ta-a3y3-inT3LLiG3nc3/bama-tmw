import SwiftUI
import AppKit
import ConsoleCore

extension Color {
    init(hex: Int) { let (r, g, b) = M3taTokens.rgb(hex); self.init(.sRGB, red: r, green: g, blue: b) }
    /// Adaptive TMW Cosmic Lightbody color (light = Lightbody Day, dark = onyx).
    static func tmw(_ k: KeyPath<TMWTokens.Palette, Int>) -> Color {
        Color(nsColor: NSColor(name: nil) { a in
            let dark = a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let (r, g, b) = M3taTokens.rgb((dark ? TMWTokens.dark : TMWTokens.light)[keyPath: k])
            return NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
        })
    }
    // Legacy names kept so call sites stay stable; now mapped to TMW tokens.
    static let m3taNavy = Color(hex: TMWTokens.onyx)       // brand mark fill
    static let m3taGold = tmw(\.accent)                    // primary accent: cosmic red
    static func adaptive(dark: Int, light: Int) -> Color {
        Color(nsColor: NSColor(name: nil) { a in
            let (r, g, b) = M3taTokens.rgb(a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light)
            return NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
        })
    }
    static let kenteGold = Color(hex: KenteTokens.gold)                                   // fill/icon only
    static let kenteGoldText = adaptive(dark: KenteTokens.gold, light: KenteTokens.goldDeep) // text-safe gold
    static let statusGood = adaptive(dark: StatusTokens.good(dark: true), light: StatusTokens.good(dark: false))
    static let statusWarn = adaptive(dark: StatusTokens.warn(dark: true), light: StatusTokens.warn(dark: false))
    static let statusBad = adaptive(dark: StatusTokens.bad(dark: true), light: StatusTokens.bad(dark: false))
    static let tmwBg = tmw(\.bg), tmwSurface = tmw(\.surface), tmwLink = tmw(\.link), tmwGlow = tmw(\.accent2)
}

enum Appearance: String, CaseIterable, Identifiable {
    case system = "System", light = "Light", dark = "Dark"
    var id: String { rawValue }
    var scheme: ColorScheme? { switch self { case .system: nil; case .light: .light; case .dark: .dark } }
}

/// Liquid Glass status tile. Gold is concentrated in the icon only (never flooded).
struct StatusCard: View {
    let title: String, value: String, detail: String, icon: String
    var tone: Tone = .neutral
    enum Tone { case good, warn, bad, neutral }
    var toneColor: Color { switch tone { case .good: .statusGood; case .warn: .statusWarn; case .bad: .statusBad; case .neutral: .secondary } }
    var body: some View {
        VStack(alignment: .leading, spacing: M3taTokens.Spacing.s) {
            HStack {
                Image(systemName: icon).foregroundStyle(Color.m3taGold).font(.title3)
                Spacer()
                Circle().fill(toneColor).frame(width: 8, height: 8).accessibilityHidden(true)
            }
            Text(value).font(.system(.title, design: .rounded).weight(.semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            Text(title).font(.callout.weight(.medium))
            Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }
        .padding(M3taTokens.Spacing.l)
        .frame(maxWidth: .infinity, minHeight: 150, maxHeight: 150, alignment: .topLeading)
        .glassEffect(.regular, in: .rect(cornerRadius: M3taTokens.Radius.tile))
        .overlay(alignment: .leading) { UnevenRoundedRectangle(topLeadingRadius: M3taTokens.Radius.tile, bottomLeadingRadius: M3taTokens.Radius.tile).fill(Color.kenteGold).frame(width: 3).accessibilityHidden(true) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value). \(detail)")
    }
}

struct BrandHeader: View {
    var body: some View {
        HStack(spacing: M3taTokens.Spacing.s) {
            RoundedRectangle(cornerRadius: 6).fill(Color.m3taNavy).frame(width: 26, height: 26)
                .overlay(Image(systemName: "cube.transparent").font(.caption.bold()).foregroundStyle(Color.kenteGold))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text("M3ta-OS").font(.headline)
                Text("Console").font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.horizontal, M3taTokens.Spacing.s).padding(.vertical, M3taTokens.Spacing.xs)
         .accessibilityElement(children: .combine).accessibilityLabel("M3ta-OS Console")
    }
}

struct OverviewView: View {
    @Environment(Store.self) var store
    @Environment(BotStore.self) var bots
    @State private var copilot: CopilotHealth.Result?
    @State private var brain: BrainClient.StatusOutcome?
    @State private var models: ModelRoute.Outcome?
    let cols = [GridItem(.adaptive(minimum: 210), spacing: M3taTokens.Spacing.l)]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: M3taTokens.Spacing.xl) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Overview").font(.largeTitle.bold())
                    Text("One look at the mesh, from saved snapshots plus two read-only loopback checks.").foregroundStyle(.secondary)
                }
                LazyVGrid(columns: cols, alignment: .leading, spacing: M3taTokens.Spacing.l) {
                    if let s = store.state {
                        let age = SnapshotAge.describe(s.capturedAt).replacingOccurrences(of: "Snapshot ", with: "")
                        StatusCard(title: "Snapshot age", value: String(age.split(separator: "(").first ?? Substring(age)).trimmingCharacters(in: .whitespaces), detail: "Captured \(s.capturedAt) · \(store.sourcePath ?? "?")", icon: "clock", tone: .neutral)
                        let paired = s.pluto.pairing?.paired
                        StatusCard(title: "Pairing", value: paired == true ? "Paired" : paired == false ? "Not paired" : "Unknown", detail: "Never guessed; unknown stays unknown", icon: "link", tone: paired == true ? .good : .warn)
                    }
                    if let m = bots.map {
                        StatusCard(title: "OpenBot bots", value: "\(m.counts.openbot_bots)", detail: "\(m.counts.mapped_to_orbit) mapped to Orbit · \(m.counts.mapped_to_grokbot) to Grok Bot", icon: "person.3", tone: m.counts.mapped_to_orbit == m.counts.openbot_bots ? .good : .warn)
                        StatusCard(title: "Orbit agents", value: "\(m.counts.orbit_agents)", detail: "Workspace roster at map time", icon: "circle.hexagongrid", tone: .neutral)
                        StatusCard(title: "Grok Bot agents", value: "\(m.counts.grokbot_agents)", detail: "Teammates on the box", icon: "sparkle", tone: .neutral)
                        StatusCard(title: "Conflicts", value: "\(m.conflicts.count)", detail: m.conflicts.first ?? "None", icon: "exclamationmark.triangle", tone: m.conflicts.isEmpty ? .good : .bad)
                        StatusCard(title: "Brain-wired bots", value: "\(m.bots.filter { $0.brainWired == true }.count) / \(m.bots.count)", detail: "From each bot's config", icon: "brain", tone: m.bots.contains { $0.brainWired == true } ? .good : .warn)
                    }
                    StatusCard(title: "Brain (rea-mcp)", value: { switch brain { case .none: "Checking…"; case .online: "Reachable"; case .offline: "Offline" } }(), detail: "127.0.0.1:9783, read-only", icon: "brain.head.profile", tone: { switch brain { case .none: .neutral; case .online: .good; case .offline: .bad } }())
                    StatusCard(title: "Copilot (JARVIS)", value: { switch copilot { case .none: "Checking…"; case .online: "Reachable"; case .offline: "Offline" } }(), detail: "127.0.0.1:9782, never started from here", icon: "sparkles", tone: { switch copilot { case .none: .neutral; case .online: .good; case .offline: .bad } }())
                    StatusCard(title: "Models (JARVIS)", value: { switch models { case .none: "Checking…"; case .ok(let r): r.default.model; case .offline: "Offline" } }(), detail: { switch models { case .ok(let r): "Fallback \(r.fallback ?? "?") · paid on: \(r.paidEnabledCount) · JEV cap $\(Int(r.jev?.daily_usd_cap ?? 0))"; case .offline(let e): e; case .none: "127.0.0.1:9782/api/models, read-only" } }(), icon: "cpu", tone: { switch models { case .ok(let r): r.default.paid ? .warn : .good; case .offline: .bad; case .none: .neutral } }())
                }
            }.padding(M3taTokens.Spacing.xl)
        }
        .task { async let c = CopilotHealth.check(); async let b = BrainClient.status(); async let m = ModelRoute.fetch(); copilot = await c; brain = await b; models = await m }
    }
}

/// Kente stripe divider (fills only, 4pt; part of the ≤15% accent budget).
struct KenteStripe: View {
    var body: some View {
        HStack(spacing: 0) { ForEach(Array(KenteTokens.stripe.enumerated()), id: \.offset) { Color(hex: $0.element) } }
            .frame(height: 4).accessibilityHidden(true)
    }
}

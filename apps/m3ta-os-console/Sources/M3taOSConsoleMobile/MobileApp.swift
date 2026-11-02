import SwiftUI
import ConsoleCore

/// M3ta-OS Console mobile companion (iPhone + iPad), sharing ConsoleCore
/// with the desktop Console: same DashboardState contract, same loader,
/// same system-1 dashboard tokens.
///
/// Scope per the 2026-11-02 research pattern: mobile is glance +
/// approvals only. The companion renders the bundled snapshot (a
/// producer-refreshed file rides a later sync step; the loader contract
/// is the same one the desktop uses). JARVIS lives on the Mac, so the
/// loopback probes cannot answer from a phone: the approvals count
/// renders "Unknown" with that reason on its face, never a guessed
/// zero, and no queue detail is shown. No push notifications are
/// implemented in this round, so nothing sensitive can leak into one.
@main
struct M3taOSConsoleMobileApp: App {
    var body: some Scene {
        WindowGroup("M3ta-OS Companion") { MobileDashboardView() }
    }
}

private extension Color {
    init(dashHex hex: Int) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
    static let mBg = Color(dashHex: DashboardTokens.standard.bg)
    static let mSurface = Color(dashHex: DashboardTokens.standard.surface)
    static let mText = Color(dashHex: DashboardTokens.standard.text)
    static let mMuted = Color(dashHex: DashboardTokens.standard.textMuted)
    static let mAccent = Color(dashHex: DashboardTokens.standard.accent)
    static let mAccent2 = Color(dashHex: DashboardTokens.standard.accent2)
    static func mSlot(_ s: DashboardStatus) -> Color { Color(dashHex: s.slotHex) }
}

struct MobileDashboardView: View {
    @State private var state: DashboardState?
    @State private var loadError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let s = state {
                        glance(s)
                        approvals
                        surfaces(s)
                    } else {
                        Text("No snapshot loaded").font(.headline).foregroundStyle(Color.mText)
                        if let e = loadError { Text(e).font(.caption).foregroundStyle(Color.mSlot(.blocked)) }
                    }
                }
                .padding(16)
            }
            .background(Color.mBg)
            .navigationTitle("M3ta Way Dashboard")
            .task {
                do { state = try DashboardStateLoader.loadBundled() }
                catch { loadError = "Could not load DashboardState: \(error.localizedDescription)" }
            }
        }
    }

    // Glance: the ranked brief, the ticker items as a static list, and
    // the dated verified revenue line. Nothing is collected on open.
    private func glance(_ s: DashboardState) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Today").font(.title2.bold()).foregroundStyle(Color.mText)
            Text(s.ageDescription).font(.caption).foregroundStyle(Color.mMuted)
            ForEach(Array(s.rankedBriefLines().enumerated()), id: \.offset) { _, line in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(line.kind.rawValue).font(.caption.monospaced().weight(.semibold)).foregroundStyle(Color.mAccent2)
                    Text(line.text).font(.callout).foregroundStyle(Color.mText)
                }
            }
            if let items = s.tickerItems {
                Divider().overlay(Color.mMuted.opacity(0.4))
                ForEach(Array(items.prefix(5).enumerated()), id: \.offset) { _, item in
                    Text("\(item.text) (\(item.sourceTag))").font(.caption).foregroundStyle(Color.mMuted)
                }
            }
            if let r = s.revenue, let line = r.verifiedRevenueLine {
                Text("Verified revenue to date: \(line) (empire audit, \(r.verifiedRevenueAsOf ?? "date unknown")).")
                    .font(.callout.weight(.medium)).foregroundStyle(Color.mText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.mSurface, in: .rect(cornerRadius: 14))
    }

    // Approvals: the count is a Mac-loopback probe; from a phone it is
    // honestly Unknown. Queue detail stays on the desktop strip.
    private var approvals: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Approvals").font(.headline).foregroundStyle(Color.mText)
                Spacer()
                Text("Queue detail: blocked").font(.caption.monospaced())
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Color.mSlot(.blocked).opacity(0.18), in: .capsule)
                    .foregroundStyle(Color.mSlot(.blocked))
            }
            Text("Pending count: Unknown").font(.title3.weight(.semibold)).foregroundStyle(Color.mText)
            Text("The count is a rea-mcp probe on the Mac loopback; it cannot be read from this device. Decisions happen on the desktop approvals strip, through the Jev gate.")
                .font(.caption).foregroundStyle(Color.mMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.mSurface, in: .rect(cornerRadius: 14))
    }

    private func surfaces(_ s: DashboardState) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Command surfaces").font(.headline).foregroundStyle(Color.mText)
            ForEach(Array(s.panel4OrderedSurfaces().enumerated()), id: \.offset) { _, r in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(r.name).font(.callout.weight(.medium)).foregroundStyle(Color.mText)
                    Text(r.status.word).font(.caption.monospaced())
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Color.mSlot(r.status).opacity(0.18), in: .capsule)
                        .foregroundStyle(Color.mSlot(r.status))
                    if let c = r.count { Text("\(c)").font(.callout.monospaced()).foregroundStyle(Color.mText) }
                    Spacer()
                }
                if let n = r.note { Text(n).font(.caption).foregroundStyle(Color.mMuted).lineLimit(2) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.mSurface, in: .rect(cornerRadius: 14))
    }
}

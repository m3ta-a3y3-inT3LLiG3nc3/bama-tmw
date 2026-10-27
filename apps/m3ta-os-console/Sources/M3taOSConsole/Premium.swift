import SwiftUI
import AppKit
import WebKit
import LocalAuthentication
import ConsoleCore

/// Touch ID (falls back to Mac password). Local only.
struct TouchIDAuth: OwnerAuthenticator {
    func authenticate(reason: String) async -> Bool {
        let ctx = LAContext(); var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else { return false }
        return (try? await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }
}

enum LocalLauncher {
    @Sendable static func open(_ app: String) async {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/open"); p.arguments = ["-a", app]; try? p.run()
    }
}

// MARK: M4 design primitives
struct SectionHeader: View {
    let title: String, subtitle: String, icon: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: icon).font(.title2.weight(.semibold)).foregroundStyle(Color.m3taGold).symbolEffect(.pulse, options: .repeating.speed(0.4))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(.largeTitle, design: .rounded).weight(.bold))
                Text(subtitle).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

struct GlassCard<C: View>: View {
    @ViewBuilder var content: C
    var body: some View {
        content.padding(M3taTokens.Spacing.l).frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: M3taTokens.Radius.tile))
    }
}

// MARK: M3 approvals screen
struct ApprovalsView: View {
    @Environment(ApprovalGate.self) var gate
    @State private var busy: UUID?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: M3taTokens.Spacing.xl) {
                SectionHeader(title: "Approvals", subtitle: "JEV gate · paid actions need Touch ID · approve runs once, deny never runs", icon: "checkmark.shield")
                GlassEffectContainer {
                    HStack(spacing: 12) {
                        ForEach(gate.rules, id: \.name) { r in
                            StatusCard(title: "JEV · \(r.name)", value: String(format: "$%.2f/day", r.dailyUSDCap), detail: r.dailyUSDCap == 0 ? "Paid calls blocked (cap $0)" : "Touch ID per call", icon: "gauge.with.dots.needle.33percent", tone: r.dailyUSDCap == 0 ? .warn : .good)
                        }
                        if gate.rules.isEmpty { StatusCard(title: "JEV rules", value: "None", detail: "~/.config/m3ta/jev/rules is empty", icon: "exclamationmark.shield", tone: .warn) }
                    }
                }
                Text("Waiting").font(.title3.weight(.semibold))
                if gate.pending.isEmpty {
                    ContentUnavailableView("Inbox clear", systemImage: "tray", description: Text("Nothing is waiting on you."))
                }
                ForEach(gate.pending) { a in
                    GlassCard {
                        HStack(alignment: .center, spacing: 14) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(a.title).font(.headline)
                                Text(a.detail).font(.callout).foregroundStyle(.secondary)
                                VerdictChip(v: gate.verdict(for: a), cost: a.costUSD)
                            }
                            Spacer()
                            Button("Deny", role: .destructive) { gate.deny(a.id) }.buttonStyle(.glass).disabled(busy == a.id)
                            Button { busy = a.id; Task { await gate.approve(a.id); busy = nil } } label: {
                                Label(gate.verdict(for: a) == .needsOwner ? "Approve with Touch ID" : "Approve", systemImage: gate.verdict(for: a) == .needsOwner ? "touchid" : "checkmark")
                            }.buttonStyle(.glassProminent).disabled(busy == a.id)
                        }
                    }.transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .scale.combined(with: .opacity)))
                }
                if !gate.history.isEmpty {
                    Text("History").font(.title3.weight(.semibold))
                    ForEach(gate.history, id: \.id) { h in
                        LabeledContent(h.title) { Text("\(h.outcome.rawValue) · \(h.at.formatted(date: .omitted, time: .shortened))").foregroundStyle(h.outcome == .approved ? Color.statusGood : .secondary) }
                    }
                }
                HStack {
                    Menu("Queue a local action") {
                        ForEach(EmbeddedApp.all) { e in Button("Launch \(e.name) ($0)") { gate.enqueue(GatedAction(title: "Launch \(e.name)", detail: "Opens the local desktop app · $0") { await LocalLauncher.open(e.appName) }) } }
                        Button("Test paid call via nexos ($0.01)") { gate.enqueue(GatedAction(title: "nexos test call", detail: "Gated paid fallback · demo, makes no request", provider: "nexos", costUSD: 0.01) {}) }
                    }.fixedSize()
                    Button("Reload rules") { gate.rules = JevGate.loadRules() }
                }
            }.padding(M3taTokens.Spacing.xl).animation(.spring(duration: 0.35), value: gate.pending.map(\.id))
        }
    }
}

struct VerdictChip: View {
    let v: JevVerdict, cost: Double
    var body: some View {
        let (t, c): (String, Color) = switch v {
        case .allow: ("Local · $0", .statusGood)
        case .needsOwner: (String(format: "Paid $%.2f · Touch ID", cost), .statusWarn)
        case .blocked(let why): (why, .statusBad)
        }
        Text(t).font(.caption.monospaced()).padding(.horizontal, 8).padding(.vertical, 3).background(c.opacity(0.16), in: .capsule).foregroundStyle(c)
    }
}

// MARK: M6 embedded apps
struct LocalWebView: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> WKWebView {
        let w = WKWebView(frame: .zero, configuration: WKWebViewConfiguration()); w.navigationDelegate = context.coordinator; w.setValue(false, forKey: "drawsBackground"); w.load(URLRequest(url: url)); return w
    }
    func updateNSView(_ w: WKWebView, context: Context) { if w.url?.port != url.port { w.load(URLRequest(url: url)) } }
    func makeCoordinator() -> Guard { Guard() }
    /// Blocks navigation off loopback; external links open in the default browser only on click.
    final class Guard: NSObject, WKNavigationDelegate {
        func webView(_ w: WKWebView, decidePolicyFor a: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard let u = a.request.url else { return .cancel }
            if EmbeddedApp.isLoopback(u) || u.scheme == "about" { return .allow }
            if a.navigationType == .linkActivated { NSWorkspace.shared.open(u) }
            return .cancel
        }
    }
}

struct EmbedView: View {
    let app: EmbeddedApp
    @Environment(ApprovalGate.self) var gate
    @AppStorage private var port: Int
    @State private var online: Bool?
    init(app: EmbeddedApp) { self.app = app; _port = AppStorage(wrappedValue: app.defaultPort, "embedPort.\(app.id)") }
    var body: some View {
        Group {
            switch online {
            case .none: ProgressView("Looking for \(app.name) on 127.0.0.1:\(port)…")
            case .some(true): LocalWebView(url: app.url(port: port)).clipShape(.rect(cornerRadius: M3taTokens.Radius.tile)).padding(8)
            case .some(false):
                VStack(spacing: 18) {
                    ContentUnavailableView("\(app.name) is offline", systemImage: app.icon, description: Text("Nothing answers on 127.0.0.1:\(port). Launching is queued in Approvals, never started silently."))
                    HStack {
                        TextField("Port", value: $port, format: .number.grouping(.never)).frame(width: 90).textFieldStyle(.roundedBorder)
                        Button("Retry") { Task { await probe() } }.buttonStyle(.glass)
                        Button("Queue launch") { gate.enqueue(GatedAction(title: "Launch \(app.name)", detail: "Opens the local desktop app · $0") { await LocalLauncher.open(app.appName) }) }.buttonStyle(.glassProminent)
                    }
                }.frame(maxWidth: 520)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity).task(id: port) { await probe() }
    }
    func probe() async {
        online = nil; var r = URLRequest(url: app.url(port: port)); r.timeoutInterval = 2
        online = ((try? await URLSession.shared.data(for: r))?.1 as? HTTPURLResponse) != nil
    }
}

// MARK: Menu bar extra
struct MenuBarPanel: View {
    @Environment(ApprovalGate.self) var gate
    @Environment(\.openWindow) var openWindow
    @State private var jarvis: CopilotHealth.Result?
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { BrandHeader(); Spacer() }
            LabeledContent("JARVIS 9782") { Text({ if case .online = jarvis { return "online" }; return jarvis == nil ? "…" : "offline" }()) }
            LabeledContent("Approvals waiting") { Text("\(gate.pending.count)").monospacedDigit() }
            ForEach(gate.pending.prefix(3)) { a in Text("• \(a.title)").font(.caption).lineLimit(1) }
            Divider()
            Button("Open Console") { NSApp.activate(); openWindow(id: "console") }
        }.padding(14).frame(width: 280).task { jarvis = await CopilotHealth.check() }
    }
}

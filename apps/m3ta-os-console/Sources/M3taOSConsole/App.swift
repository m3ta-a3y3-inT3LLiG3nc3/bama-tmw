import SwiftUI
import AppKit
import ConsoleCore

@MainActor @Observable
final class Store {
    var state: MeshState?
    var error: String?
    var sourcePath: String?
    init() { refresh() }
    /// Manual refresh: re-reads the override JSON if set in Settings, else the bundled fixture.
    func refresh() {
        do {
            if let p = UserDefaults.standard.string(forKey: "meshStatePath"), !p.isEmpty {
                state = try MeshStateLoader.load(from: URL(fileURLWithPath: (p as NSString).expandingTildeInPath)); sourcePath = p
            } else {
                state = try MeshStateLoader.loadBundled(); sourcePath = "bundled fixture"
            }
            error = nil
        } catch { self.error = "Could not load MeshState: \(error.localizedDescription)" }
    }
}

enum Screen: String, CaseIterable, Identifiable {
    case overview = "Overview", status = "Pluto status", pairing = "Pairing", result = "Pairing result", mesh = "Mesh", bots = "Bots", brain = "Brain", copilot = "Copilot"
    var id: String { rawValue }
    static let groups: [(String, [Screen])] = [("Home", [.overview]), ("Pluto", [.status, .pairing, .result]), ("Mesh", [.mesh, .bots, .brain]), ("Assist", [.copilot])]
    var story: String { switch self { case .overview: "M2-HOME"; case .status: "S-001"; case .pairing: "S-002"; case .result: "S-003"; case .mesh: "S-006"; case .bots: "M2-BOTS"; case .brain: "M2-BRAIN"; case .copilot: "S-007" } }
    var icon: String { switch self { case .overview: "square.grid.2x2"; case .status: "antenna.radiowaves.left.and.right"; case .pairing: "link"; case .result: "checkmark.seal"; case .mesh: "square.grid.3x3"; case .bots: "person.3"; case .brain: "brain"; case .copilot: "sparkles" } }
}

@main
struct M3taOSConsoleApp: App {
    @State private var store = Store()
    @State private var bots = BotStore()
    @AppStorage("appearance") private var appearance = Appearance.dark.rawValue
    init() { NSApplication.shared.setActivationPolicy(.regular) }
    var body: some Scene {
        WindowGroup("M3ta-OS Console") { RootView().environment(store).environment(bots).frame(minWidth: 960, minHeight: 640).tint(.m3taGold).preferredColorScheme(Appearance(rawValue: appearance)?.scheme) }
        Settings { SettingsView().environment(store).environment(bots) }
    }
}

struct RootView: View {
    @Environment(Store.self) var store
    @Environment(BotStore.self) var bots
    @State private var sel: Screen? = Screen(rawValue: ProcessInfo.processInfo.environment["CONSOLE_SCREEN"] ?? "") ?? .overview
    var body: some View {
        NavigationSplitView {
            List(selection: $sel) {
                BrandHeader().listRowSeparator(.hidden)
                ForEach(Screen.groups, id: \.0) { g in
                    Section(g.0) { ForEach(g.1) { s in Label(s.rawValue, systemImage: s.icon).tag(s).accessibilityHint("Shows the \(s.rawValue) screen") } }
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 220)
        } detail: {
            if let st = store.state {
                Group {
                    switch sel ?? .overview {
                    case .overview: OverviewView()
                    case .status: StatusView(s: st)
                    case .pairing: PairingView(s: st)
                    case .result: ResultView(s: st)
                    case .mesh: MeshView(s: st)
                    case .bots: BotsView()
                    case .brain: BrainView()
                    case .copilot: JarvisLiveView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                // Banner reserves its own space so scrolling content never sits under it.
                .safeAreaInset(edge: .top, spacing: 0) { if sel != .overview { AgeBanner(state: st) } }
            } else if store.state == nil && store.error == nil { ProgressView("Loading snapshot…")
            } else { ContentUnavailableView("No state", systemImage: "exclamationmark.triangle", description: Text(store.error ?? "")) }
        }
        .background(Color.tmwBg)
        .toolbar { Button("Refresh", systemImage: "arrow.clockwise") { store.refresh(); bots.refresh(); NotificationCenter.default.post(name: .consoleRefresh, object: nil) }.keyboardShortcut("r") }
    }
}

struct AgeBanner: View {
    let state: MeshState
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(SnapshotAge.describe(state.capturedAt), systemImage: "clock").font(.callout.weight(.medium))
            Text("Source: \(state.source)").font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
         .background(Color.m3taGold.opacity(0.12)).overlay(alignment: .leading) { Rectangle().fill(Color.m3taGold).frame(width: 3) }
         .accessibilityElement(children: .combine)
    }
}

func row(_ k: String, _ v: String) -> some View {
    LabeledContent(k) { Text(v).textSelection(.enabled) }
}

struct StatusView: View {
    let s: MeshState
    var p: MeshState.Pluto { s.pluto }
    var body: some View {
        Form {
            Section("Instance") {
                row("Instance id", p.instanceId)
                row("Name", p.instanceName ?? "Unknown")
                row("Plan", p.plan ?? "Unknown")
                row("Deployment (reported)", p.deployment ?? "Unknown")
                row("Credits", p.creditsRemainingUSD.map { String(format: "$%.2f", $0) } ?? "Unknown")
                row("Refill", p.creditsRefillDate ?? "Unknown")
            }
            Section("iMessage") {
                row("State", p.imessage?.state ?? "Unknown")
                row("Features", p.imessage?.featuresOn ?? "Unknown")
                Text("The phone thread is ground truth. \(p.imessage?.loopVerified ?? "")").font(.caption).foregroundStyle(.secondary)
                if let w = p.testTextWart { Text(w).font(.caption).foregroundStyle(.orange) }
            }
            Section("Connected apps (\(p.apps.count))") {
                ForEach(p.apps) { a in row(a.name, "\(a.state ?? "Unknown") · \(a.account ?? "")") }
                switch p.notionHeld {
                case .some(true): row("Notion", "Held for page curation")
                case .some(false): row("Notion", "Not held")
                case .none: row("Notion", "Unknown")
                }
            }
        }.formStyle(.grouped)
    }
}

struct PairingView: View {
    let s: MeshState
    var body: some View {
        Form {
            if let pr = s.pluto.pairing {
                Section("\(pr.app ?? "Ruth Local") pairing") {
                    ForEach(pr.states(), id: \.0) { step, st in
                        HStack {
                            Image(systemName: { switch st { case .done: "checkmark.circle.fill"; case .next: "arrow.right.circle.fill"; case .pending: "circle"; case .unknown: "questionmark.circle" } }())
                            Text(step.rawValue).fontWeight(st == .next ? .bold : .regular)
                            Spacer()
                            Text({ switch st { case .done: "Done"; case .next: "Next action"; case .pending: "Later"; case .unknown: "Unknown" } }()).foregroundStyle(.secondary)
                        }.opacity(st == .pending ? 0.4 : 1)
                    }
                }
                Section { Text("The Connect link is single-use and expires in 10 minutes. Open it only after Ruth Local is launched.").font(.caption).foregroundStyle(.orange) }
            } else { Text("Pairing state: Unknown") }
        }.formStyle(.grouped)
    }
}

struct ResultView: View {
    let s: MeshState
    var body: some View {
        let pr = s.pluto.pairing
        Form {
            Section("Pairing result") {
                row("Pairing", { switch pr?.paired { case .some(true): "Paired"; case .some(false): "Not paired"; case .none: "Unknown" } }())
                row("Vault reach", pr?.vaultReachDisplay ?? "Unknown")
            }
            Section("Permissions (as reported, granted to Ruth Local)") {
                if let perms = pr?.permissions, !perms.isEmpty {
                    ForEach(perms.keys.sorted(), id: \.self) { k in row(k, perms[k] ?? "Unknown") }
                } else { row("Permissions", "Unknown") }
            }
        }.formStyle(.grouped)
    }
}

struct StatusTag: View {
    let status: String
    var body: some View {
        let color: Color = switch StatusStyle(status) { case .live: .green; case .built: .blue; case .partial: .orange; case .notBuilt: .red; case .retired: .gray; case .raw: .primary }
        Text(status).font(.caption.monospaced()).padding(.horizontal, 6).padding(.vertical, 2)
            .background(StatusStyle(status) == .raw ? Color.clear : color.opacity(0.18), in: .capsule)
            .foregroundStyle(color)
    }
}

struct ItemRow: View {
    let i: MeshState.Item
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading) { Text(i.name); if let n = i.note { Text(n).font(.caption).foregroundStyle(.secondary) } }
            Spacer(); StatusTag(status: i.status)
        }
    }
}

struct MeshView: View {
    let s: MeshState
    var body: some View {
        Form {
            if let m = s.mesh.mvpDeclared { Text(m).font(.caption) }
            Section("Flagship \(s.mesh.flagships.count)") { ForEach(s.mesh.flagships) { ItemRow(i: $0) } }
            ForEach(s.mesh.layers) { l in Section("Layer: \(l.name)") { ForEach(l.components) { ItemRow(i: $0) } } }
            Section("Modules (\(s.mesh.modules.count))") { ForEach(s.mesh.modules) { ItemRow(i: $0) } }
            if let r = s.mesh.relay { Section("Relay") { ItemRow(i: .init(name: r.name, status: r.status, note: r.evidence)) } }
        }.formStyle(.grouped)
    }
}

struct CopilotStub: View {
    @State private var result: CopilotHealth.Result?
    @State private var checking = false
    var body: some View {
        VStack(spacing: 16) {
            switch result {
            case .none: ProgressView("Checking JARVIS runtime on 127.0.0.1:9782…")
            case .online(let c): ContentUnavailableView("JARVIS runtime reachable", systemImage: "sparkles", description: Text("HTTP \(c). The chat panel is wired in M5."))
            case .offline(let why):
                ContentUnavailableView("Copilot offline", systemImage: "bolt.horizontal.circle", description: Text("JARVIS runtime at 127.0.0.1:9782 is not answering (\(why)). The rest of the console still works. This panel never starts JARVIS."))
            }
            Button("Retry") { Task { await check() } }.disabled(checking)
        }.padding().frame(maxWidth: .infinity, maxHeight: .infinity).task { await check() }
    }
    func check() async { checking = true; result = await CopilotHealth.check(); checking = false }
}

struct SettingsView: View {
    @Environment(Store.self) var store
    @Environment(BotStore.self) var bots
    @AppStorage("meshStatePath") private var path = ""
    @AppStorage("botMapPath") private var botPath = ""
    @AppStorage("appearance") private var appearance = Appearance.dark.rawValue
    @AppStorage("jarvisRuntimePort") private var runtimePort = 9782
    @AppStorage("jarvisReaPort") private var reaPort = 9783
    @AppStorage("jarvisRefreshSeconds") private var refreshSeconds = 10
    var body: some View {
        Form {
            Section("JARVIS endpoint (host is always 127.0.0.1)") {
                TextField("agent-runtime port", value: $runtimePort, format: .number.grouping(.never))
                TextField("rea-mcp port", value: $reaPort, format: .number.grouping(.never))
                Stepper("Auto-refresh every \(refreshSeconds)s", value: $refreshSeconds, in: 5...120, step: 5)
                Button("Reset to 9782 / 9783") { runtimePort = 9782; reaPort = 9783 }
            }
            TextField("MeshState JSON path (empty = bundled fixture)", text: $path)
            Text("Loaded from: \(store.sourcePath ?? "none")").font(.caption)
            Picker("Appearance", selection: $appearance) { ForEach(Appearance.allCases) { Text($0.rawValue).tag($0.rawValue) } }
            TextField("Bot map JSON path (empty = bundled copy)", text: $botPath)
            Text("Bot map from: \(bots.sourcePath)").font(.caption)
            Button("Reload") { store.refresh(); bots.refresh() }
            Text("No secrets are stored. JARVIS checks are read-only GETs on loopback; the console never starts JARVIS.").font(.caption).foregroundStyle(.secondary)
        }.padding().frame(width: 460)
    }
}

extension Notification.Name { static let consoleRefresh = Notification.Name("os.m3ta.console.refresh") }

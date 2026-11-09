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

/// Owns the loaded DashboardState (dashboard spec, data contract).
/// Deliberate deviation from BotStore: when a Settings override path is
/// set and fails, the error shows and no bundled fixture is substituted,
/// because falling back to a stale fixture while claiming freshness is
/// the failure the dashboard design exists to prevent.
@MainActor @Observable
final class DashboardStore {
    var state: DashboardState?
    var error: String?
    var sourcePath: String?
    init() { refresh() }
    func refresh() {
        do {
            if let p = UserDefaults.standard.string(forKey: "dashboardStatePath"), !p.isEmpty {
                state = try DashboardStateLoader.load(from: URL(fileURLWithPath: (p as NSString).expandingTildeInPath)); sourcePath = p
            } else {
                state = try DashboardStateLoader.loadBundled(); sourcePath = "bundled fixture"
            }
            error = nil
        } catch { state = nil; self.error = "Could not load DashboardState: \(error.localizedDescription)" }
    }
}

enum Screen: String, CaseIterable, Identifiable {
    case lookout = "Lookout", vault = "Vault", boards = "Boards", ideas = "Ideas", dashboard = "Dashboard", overview = "Overview", status = "Pluto status", pairing = "Pairing", result = "Pairing result", mesh = "Mesh", bots = "Bots", brain = "Brain", copilot = "Copilot"
    var id: String { rawValue }
    static let groups: [(String, [Screen])] = [("Command", [.lookout, .vault, .boards, .ideas, .dashboard]), ("Home", [.overview]), ("Pluto", [.status, .pairing, .result]), ("Mesh", [.mesh, .bots, .brain]), ("Assist", [.copilot])]
    var story: String { switch self { case .lookout: "FB-1"; case .vault: "FB-2"; case .boards: "FB-3"; case .ideas: "FB-4"; case .dashboard: "M3-DASH"; case .overview: "M2-HOME"; case .status: "S-001"; case .pairing: "S-002"; case .result: "S-003"; case .mesh: "S-006"; case .bots: "M2-BOTS"; case .brain: "M2-BRAIN"; case .copilot: "S-007" } }
    var icon: String { switch self { case .lookout: "binoculars"; case .vault: "folder"; case .boards: "rectangle.split.3x1"; case .ideas: "lightbulb"; case .dashboard: "gauge"; case .overview: "square.grid.2x2"; case .status: "antenna.radiowaves.left.and.right"; case .pairing: "link"; case .result: "checkmark.seal"; case .mesh: "square.grid.3x3"; case .bots: "person.3"; case .brain: "brain"; case .copilot: "sparkles" } }
}

/// Window recovery (Phase 2 defect lane, 2026-11-09): the app was observed
/// running with ZERO windows after a relaunch (index pass done, nothing on
/// screen) until a manual reopen. RootView registers an openWindow action
/// here; the delegate re-presents the main window whenever the app
/// finishes launching or becomes active with no visible main window.
enum WindowRecovery {
    nonisolated(unsafe) static var openMainWindow: (() -> Void)?
    nonisolated(unsafe) static var fallbackWindow: NSWindow?
    nonisolated(unsafe) static var windowlessSince: Date?
    /// Window-recovery debug mirror (same rationale as the calendar
    /// debug log: the unified log is unreadable on the target Mac).
    static func wlog(_ message: String) {
        let line = "\(Date()) WR \(message)\n"
        let url = URL(fileURLWithPath: "/tmp/console-window-debug.log")
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(line.utf8))
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }
    @MainActor static func ensureVisibleWindow() {
        let hasWindow = NSApp.windows.contains { $0.isVisible && $0.canBecomeMain }
        let frames = NSApp.windows.map { "[\($0.title) vis=\($0.isVisible) frame=\(NSStringFromRect($0.frame)) screen=\($0.screen?.localizedName ?? "nil") space=\($0.collectionBehavior.rawValue)]" }.joined(separator: " ")
        wlog("ensure: windows=\(NSApp.windows.count) visible=\(NSApp.windows.filter { $0.isVisible }.count) hasWindow=\(hasWindow) openRegistered=\(openMainWindow != nil) fallback=\(fallbackWindow != nil) frames=\(frames)")
        if hasWindow { windowlessSince = nil; return }
        NSApp.activate(ignoringOtherApps: true)
        if let openMainWindow {
            openMainWindow()
            windowlessSince = nil
            return
        }
        // Chicken-and-egg case (observed repeatedly 2026-11-09, no
        // env/launch-mode pattern): the SwiftUI scene never instantiated
        // its first window, so openWindow was never registered and the
        // openWindow path can never fire. After a grace period, build a
        // plain AppKit fallback window hosting the same RootView on its
        // own store instances — same files, same watcher reconciliation;
        // a degraded window beats a windowless process.
        let now = Date()
        if windowlessSince == nil { windowlessSince = now }
        guard let since = windowlessSince, now.timeIntervalSince(since) > 4 else { return }
        wlog("building fallback window")
        buildFallbackWindow()
        wlog("fallback built: visible=\(fallbackWindow?.isVisible ?? false)")
        windowlessSince = nil
    }
    @MainActor private static func buildFallbackWindow() {
        let root = RootView()
            .environment(Store())
            .environment(BotStore())
            .environment(DashboardStore())
            .environment(ChatRunStore())
            .environment(FieldBookStore())
            .frame(minWidth: 960, minHeight: 640)
            .tint(.m3taGold)
        let window = NSWindow(contentViewController: NSHostingController(rootView: root))
        window.title = "M3ta-OS Console"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.setContentSize(NSSize(width: 1500, height: 950))
        window.center()
        window.makeKeyAndOrderFront(nil)
        fallbackWindow = window
    }
}

/// Phase 1 fix F4: full-screen Space is the default launch posture,
/// applied by the app's own code at launch (never restored window state).
/// CONSOLE_NO_FULLSCREEN=1 is the scripted-probe opt-out (LaunchPosture).
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowWatchdog: Timer?
    private var activityToken: NSObjectProtocol?
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hold off App Nap: a windowless/backgrounded console got its
        // timers (watcher debounce, window watchdog) frozen by App Nap on
        // 2026-11-09, which is how a lost window stayed lost until a
        // manual reopen. This is an always-on daily-driver console; a
        // user-initiated activity assertion is the correct posture.
        activityToken = ProcessInfo.processInfo.beginActivity(options: .userInitiated,
                                                              reason: "M3ta-OS Console daily-driver console")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            Task { @MainActor in WindowRecovery.ensureVisibleWindow() }
        }
        // Watchdog: this is a single-window daily-driver console; a state
        // with the process alive and zero visible windows (observed twice
        // on 2026-11-09, once after a relaunch and once after synthetic
        // input churn) is never a legitimate end state, so the app
        // re-presents its main window whenever it is detected.
        windowWatchdog = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            Task { @MainActor in
                if !NSApp.windows.contains(where: { $0.isVisible }) {
                    WindowRecovery.ensureVisibleWindow()
                }
            }
        }
        guard LaunchPosture.shouldLaunchFullScreen(environment: ProcessInfo.processInfo.environment) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            guard let w = NSApp.windows.first(where: { $0.isVisible }) ?? NSApp.windows.first else { return }
            w.collectionBehavior.insert(.fullScreenPrimary)
            if !w.styleMask.contains(.fullScreen) { w.toggleFullScreen(nil) }
        }
    }
    func applicationDidBecomeActive(_ notification: Notification) {
        Task { @MainActor in WindowRecovery.ensureVisibleWindow() }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { Task { @MainActor in WindowRecovery.ensureVisibleWindow() } }
        return true
    }
}

@main
struct M3taOSConsoleApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var store = Store()
    @State private var bots = BotStore()
    @State private var dashboard = DashboardStore()
    @State private var chatRuns = ChatRunStore()
    @State private var fieldBook = FieldBookStore()
    @AppStorage("appearance") private var appearance = Appearance.dark.rawValue
    init() { NSApplication.shared.setActivationPolicy(.regular) }
    var body: some Scene {
        WindowGroup("M3ta-OS Console", id: "main") { RootView().environment(store).environment(bots).environment(dashboard).environment(chatRuns).environment(fieldBook).frame(minWidth: 960, minHeight: 640).tint(.m3taGold).preferredColorScheme(Appearance(rawValue: appearance)?.scheme) }
        Settings { SettingsView().environment(store).environment(bots).environment(dashboard) }
    }
}

struct RootView: View {
    @Environment(Store.self) var store
    @Environment(BotStore.self) var bots
    @Environment(DashboardStore.self) var dashboard
    @Environment(FieldBookStore.self) var fieldBook
    @Environment(\.scenePhase) var scenePhase
    @Environment(\.openWindow) var openWindow
    // Launch default is the Lookout (Phase 2 defect lane, 2026-11-09,
    // parent call: a relaunch restoring to Dashboard instead of the
    // Lookout home surface is a wart; this supersedes the 2026-11-02
    // Dashboard-default for LAUNCH only — Dashboard stays in the sidebar).
    // CONSOLE_SCREEN still selects a screen for scripted launches.
    @State private var sel: Screen? = Screen(rawValue: ProcessInfo.processInfo.environment["CONSOLE_SCREEN"] ?? "") ?? .lookout
    var body: some View {
        NavigationSplitView {
            List(selection: $sel) {
                BrandHeader().listRowSeparator(.hidden)
                ForEach(Screen.groups, id: \.0) { g in
                    Section(g.0) {
                        ForEach(g.1) { s in
                            // A real Button per row, not a bare Label: an
                            // AXPress (or click) on the row's static text
                            // did not switch surfaces (Phase 2 defect lane);
                            // buttons are pressable by AX and by mouse alike,
                            // and the List selection binding still tracks.
                            Button { sel = s } label: { Label(s.rawValue, systemImage: s.icon) }
                                .buttonStyle(.plain).tag(s)
                                .accessibilityHint("Shows the \(s.rawValue) screen")
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 220)
        } detail: {
            // The Dashboard is NOT gated on MeshState (spec, Root view
            // gating change): it renders from DashboardState plus the
            // loopback probes whatever MeshState did, and a DashboardState
            // failure never blocks the other screens.
            if (sel ?? .dashboard) == .lookout {
                LookoutView { rel in fieldBook.selectedRelativePath = rel; sel = .vault }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .safeAreaInset(edge: .top, spacing: 0) { KenteStripe() }
            } else if (sel ?? .dashboard) == .vault {
                VaultBrowserView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .safeAreaInset(edge: .top, spacing: 0) { KenteStripe() }
            } else if (sel ?? .dashboard) == .boards {
                BoardsView { rel in fieldBook.openEditor(relativePath: rel); sel = .vault }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .safeAreaInset(edge: .top, spacing: 0) { KenteStripe() }
            } else if (sel ?? .dashboard) == .ideas {
                IdeasView { rel in fieldBook.openEditor(relativePath: rel); sel = .vault }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .safeAreaInset(edge: .top, spacing: 0) { KenteStripe() }
            } else if (sel ?? .dashboard) == .dashboard {
                DashboardView { s in sel = s }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .safeAreaInset(edge: .top, spacing: 0) { KenteStripe() }
            } else if let st = store.state {
                Group {
                    switch sel ?? .overview {
                    case .lookout: LookoutView { rel in fieldBook.selectedRelativePath = rel; sel = .vault }
                    case .vault: VaultBrowserView()
                    case .boards: BoardsView { rel in fieldBook.openEditor(relativePath: rel); sel = .vault }
                    case .ideas: IdeasView { rel in fieldBook.openEditor(relativePath: rel); sel = .vault }
                    case .dashboard: DashboardView { s in sel = s }
                    case .overview: OverviewView()
                    case .status: StatusView(s: st)
                    case .pairing: PairingView(s: st)
                    case .result: ResultView(s: st)
                    case .mesh: MeshView(s: st)
                    case .bots: BotsView()
                    case .brain: BrainView()
                    case .copilot: CopilotPanelView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                // Banner reserves its own space so scrolling content never sits under it.
                .safeAreaInset(edge: .top, spacing: 0) { VStack(spacing: 0) { KenteStripe(); if sel != .overview { AgeBanner(state: st) } } }
            } else if store.state == nil && store.error == nil { ProgressView("Loading snapshot…")
            } else { ContentUnavailableView("No state", systemImage: "exclamationmark.triangle", description: Text(store.error ?? "")) }
        }
        .background(Color.tmwBg)
        // FB_FORCE_FALLBACK=1 is a test-only gate: it suppresses the
        // openWindow registration so the AppKit fallback window path can
        // be exercised end to end.
        .onAppear { if ProcessInfo.processInfo.environment["FB_FORCE_FALLBACK"] != "1" { WindowRecovery.openMainWindow = { openWindow(id: "main") } } }
        .onChange(of: scenePhase) { _, phase in
            // Reconciliation-on-focus (Phase 1 external-change detection).
            if phase == .active { fieldBook.reconcileOnFocus() }
        }
        .toolbar { Button("Refresh", systemImage: "arrow.clockwise") { store.refresh(); bots.refresh(); dashboard.refresh(); fieldBook.refresh(); NotificationCenter.default.post(name: .consoleRefresh, object: nil) }.keyboardShortcut("r") }
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

struct SettingsView: View {
    @Environment(Store.self) var store
    @Environment(BotStore.self) var bots
    @Environment(DashboardStore.self) var dashboard
    @AppStorage("meshStatePath") private var path = ""
    @AppStorage("botMapPath") private var botPath = ""
    @AppStorage("dashboardStatePath") private var dashPath = ""
    @AppStorage("crmBaseURL") private var crmBaseURL = ""
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
            TextField("Dashboard state JSON path (empty = bundled fixture)", text: $dashPath)
            Text("Loaded from: \(dashboard.sourcePath ?? "none")").font(.caption)
            Section("M3ta-CRM module (specs/m3ta-os-console-crm.md)") {
                TextField("CRM base URL (empty = http://localhost:3120)", text: $crmBaseURL)
                Text("The CRM bearer token is never stored here. It comes from the CRM_API_TOKEN environment variable at launch; without it the CRM tab shows its unbound screen. Base URL changes apply when the CRM tab reloads its config (Refresh).").font(.caption).foregroundStyle(.secondary)
            }
            Button("Reload") { store.refresh(); bots.refresh(); dashboard.refresh() }
            Text("No secrets are stored. JARVIS checks are read-only GETs on loopback; the console never starts JARVIS.").font(.caption).foregroundStyle(.secondary)
        }.padding().frame(width: 460)
    }
}

extension Notification.Name { static let consoleRefresh = Notification.Name("os.m3ta.console.refresh") }

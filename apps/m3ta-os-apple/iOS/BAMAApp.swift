import SwiftUI
import ConsoleCore

@main struct BAMAApp: App {
    @State private var model = AppModel()
    var body: some Scene {
        WindowGroup { RootView().environment(model).tint(.tmwGold).preferredColorScheme(.dark).task { await model.refresh() } }
    }
}

enum Tab: String, CaseIterable, Identifiable { case home = "Home", approvals = "Approvals", studio = "Studio", settings = "Settings"
    var id: String { rawValue }
    var icon: String { switch self { case .home: "square.grid.2x2"; case .approvals: "checkmark.shield"; case .studio: "sparkles.rectangle.stack"; case .settings: "gearshape" } }
}

/// Adaptive: TabView with .sidebarAdaptable → tab bar on iPhone, sidebar split view on iPad and Mac.
struct RootView: View {
    @Environment(AppModel.self) var model
    @State private var tab: Tab = Tab(rawValue: ProcessInfo.processInfo.environment["BAMA_TAB"] ?? "") ?? .home
    var body: some View {
        TabView(selection: $tab) {
            ForEach(Tab.allCases) { t in
                SwiftUI.Tab(t.rawValue, systemImage: t.icon, value: t) {
                    NavigationStack { screen(t).navigationTitle(t == .home ? "BAMA · M3ta-OS" : t.rawValue) }
                }
                .badge(t == .approvals ? model.inbox.items.count : 0)
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .onOpenURL { if $0.host() == "approvals" { tab = .approvals } }
    }
    @ViewBuilder func screen(_ t: Tab) -> some View {
        switch t { case .home: DashboardView(); case .approvals: ApprovalsView(); case .studio: StudioView(); case .settings: SettingsView() }
    }
}

struct DashboardView: View {
    @Environment(AppModel.self) var model
    var body: some View {
        ScrollView {
            GlassEffectContainer(spacing: 16) {
                VStack(spacing: 16) {
                    GlassCard { HealthBadge(g: model.glance) }
                    GlassCard {
                        HStack { Label("\(model.inbox.items.count) pending approvals", systemImage: "checkmark.shield").font(.headline); Spacer() }
                        if let top = model.inbox.items.first { Text(top.summary).font(.subheadline).foregroundStyle(.secondary) }
                    }
                    GlassCard { Label("Th3 M3ta Way · $0 local-first", systemImage: "cube.transparent").font(.subheadline) }
                    if model.isDemo { Text("Demo data — not connected to your Mac.").font(.footnote).foregroundStyle(.secondary) }
                }.padding()
            }
        }
        .background(LinearGradient(colors: [.tmwInk, .black], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
        .refreshable { await model.refresh() }
    }
}

struct ApprovalsView: View {
    @Environment(AppModel.self) var model
    var body: some View {
        List {
            if let e = model.inbox.lastError { Text(e).foregroundStyle(.orange) }
            if model.inbox.items.isEmpty { ContentUnavailableView("Nothing waiting", systemImage: "checkmark.seal") }
            ForEach(model.inbox.items) { a in
                VStack(alignment: .leading, spacing: 8) {
                    Text(a.summary).font(.headline)
                    Text("\(a.tool) · \(a.kind) · \(a.date.formatted(.relative(presentation: .named)))").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("Approve", systemImage: "faceid") { Task { await model.inbox.decide(a.id, .approve); await model.refresh() } }.buttonStyle(.glassProminent)
                        Button("Deny", systemImage: "xmark", role: .destructive) { Task { await model.inbox.decide(a.id, .deny); await model.refresh() } }.buttonStyle(.glass)
                    }
                }.padding(.vertical, 4)
            }
        }
        .refreshable { await model.refresh() }
    }
}

struct StudioView: View {
    @Environment(AppModel.self) var model
    var body: some View {
        List(EmbeddedApp.all) { app in
            LabeledContent { Text(":\(app.defaultPort)").monospaced().foregroundStyle(.secondary) } label: { Label(app.name, systemImage: app.icon) }
        }
        .safeAreaInset(edge: .bottom) {
            Text("Studio apps run on your Mac (127.0.0.1). They open here only after you OK serving them over your tailnet.").font(.footnote).foregroundStyle(.secondary).padding()
        }
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) var model
    @State private var host = ""
    var body: some View {
        Form {
            Section { TextField("kingdom-mac.tailXXXX.ts.net", text: $host).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("Save & refresh") { model.setHost(host); Task { await model.refresh() } }.disabled(!host.isEmpty && TailnetEndpoint(host: host) == nil)
            } header: { Text("Mac on your tailnet") } footer: { Text("Only *.ts.net names are accepted. Nothing is exposed publicly.") }
        }.onAppear { host = model.host }
    }
}

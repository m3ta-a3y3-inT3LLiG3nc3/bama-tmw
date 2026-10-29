import SwiftUI
import AppKit
import LocalAuthentication
import ConsoleCore

/// Touch ID through macOS LocalAuthentication. Biometrics only (no password fallback in-app);
/// jev-approve then asks the Secure Enclave key for its own Touch ID / password confirmation.
struct TouchIDAuthenticator: Authenticator {
    func authenticate(reason: String) async -> String? {
        let ctx = LAContext(); ctx.localizedFallbackTitle = ""
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err) else { return err?.localizedDescription ?? "Touch ID unavailable" }
        do { return try await ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) ? nil : "not verified" }
        catch { return error.localizedDescription }
    }
}

@MainActor @Observable
final class M3Store {
    let inbox = ApprovalInbox(ledger: ApprovalInbox.defaultLedger())
    let health = HealthChecker()
    var pending: [HeldAction] = []
    var services: [HealthResult] = []
    var skills: [SkillEntry] = []
    var message: String?
    var busy: String?
    var backendPort: Int?
    private var server: LoopbackServer?
    init() {
        reloadInbox(); skills = SkillIndex.load()
        if ProcessInfo.processInfo.environment["CONSOLE_BACKEND"] != "0" { Task { await startBackend() } }
    }
    func startBackend() async {
        let s = LoopbackServer(handler: ConsoleBackend.handler(inbox: inbox, health: health))
        do { backendPort = try await s.start(); server = s } catch { message = "Backend not started: \(error.localizedDescription)" }
    }
    func reloadInbox() { pending = inbox.pending() }
    func checkHealth() async { services = await health.checkAll() }
    func approve(_ a: HeldAction) async {
        busy = a.hash; defer { busy = nil }
        do {
            try await inbox.approve(a.hash, auth: TouchIDAuthenticator(), signer: JEVApproveSigner())
            if a.consoleOwned {
                let h = health
                switch ActionRunner(inbox: inbox).run(a.hash, execute: { h.performRestart($0) }) {
                case .ran: message = "Approved and ran once: \(a.summary)"
                case .blocked(let why): message = "Approved, but blocked: \(why). Nothing ran."
                }
            } else { message = "Approved. The agent can retry this exact action once." }
        } catch { message = "\(error)" }
        reloadInbox()
    }
    func deny(_ a: HeldAction) { do { try inbox.deny(a.hash); message = "Denied. It will never run." } catch { message = "\(error)" }; reloadInbox() }
    func requestRestart(_ id: String) {
        do { message = try health.requestRestart(id, inbox: inbox) != nil ? "Restart held for your approval in Approvals." : "Not allowed: only your own private services can restart." } catch { message = "\(error)" }
        reloadInbox()
    }
}

struct ApprovalsView: View {
    @Environment(M3Store.self) var m3
    var body: some View {
        List {
            if let msg = m3.message { Text(msg).font(.callout).foregroundStyle(.secondary) }
            if m3.pending.isEmpty { ContentUnavailableView("Nothing waiting", systemImage: "checkmark.shield", description: Text("Held actions from JEV show up here.")) }
            ForEach(m3.pending) { a in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(a.tool).font(.headline.monospaced())
                        Text(a.kind).font(.caption).foregroundStyle(.orange)
                        if !a.summary.isEmpty && a.summary != "{}" { Text(a.summary).font(.caption.monospaced()).lineLimit(2).foregroundStyle(.secondary) }
                        Text("\(Date(timeIntervalSince1970: TimeInterval(a.at)).formatted(date: .abbreviated, time: .shortened)) · \(a.hash.prefix(12))").font(.caption2).foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Button("Deny", role: .destructive) { m3.deny(a) }.disabled(m3.busy != nil)
                    Button { Task { await m3.approve(a) } } label: { Label("Approve", systemImage: "touchid") }.buttonStyle(.borderedProminent).disabled(m3.busy != nil)
                }.padding(.vertical, 4)
            }
        }
        .navigationTitle("Approvals (\(m3.pending.count))")
        .toolbar { Button("Reload", systemImage: "arrow.clockwise") { m3.reloadInbox() } }
    }
}

struct HealthView: View {
    @Environment(M3Store.self) var m3
    var body: some View {
        List {
            if let msg = m3.message { Text(msg).font(.callout).foregroundStyle(.secondary) }
            ForEach(m3.services) { s in
                HStack {
                    Image(systemName: s.up ? "checkmark.circle.fill" : "xmark.octagon.fill").foregroundStyle(s.up ? .green : .red)
                    VStack(alignment: .leading) { Text(s.name); Text(s.detail).font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    if s.restartable { Button("Restart…") { m3.requestRestart(s.id) } } else { Text("protected").font(.caption).foregroundStyle(.tertiary) }
                }
            }
            Text("Checks are loopback GETs and launchd reads, logged to ~/Library/Logs/M3taOSConsole/health.jsonl. Restarts only for your own com.m3ta / os.m3ta / com.th3m3taway agents, never JARVIS, Waypoint, Paperclip, Tailscale, Screenpipe or JEV, and only after Touch ID + JEV.").font(.caption).foregroundStyle(.secondary)
        }
        .navigationTitle("Health")
        .task { await m3.checkHealth() }
        .toolbar { Button("Check now", systemImage: "stethoscope") { Task { await m3.checkHealth() } } }
    }
}

struct HomeView: View {
    @Environment(M3Store.self) var m3
    @Environment(BotStore.self) var bots
    @State private var q = ""
    @State private var rea: [String] = []
    let cols = [GridItem(.adaptive(minimum: 210), spacing: 16)]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Home").font(.largeTitle.bold())
                    Text("Orbit, service health, approvals and skills. Everything here is on this Mac, loopback only.").foregroundStyle(.secondary)
                }
                LazyVGrid(columns: cols, alignment: .leading, spacing: 16) {
                    if let m = bots.map {
                        StatusCard(title: "Orbit", value: "\(m.counts.orbit_agents) agents", detail: "\(m.counts.mapped_to_orbit)/\(m.counts.openbot_bots) OpenBot bots mapped · runners: OpenBot, Hermes", icon: "circle.hexagongrid", tone: m.counts.mapped_to_orbit == m.counts.openbot_bots ? .good : .warn)
                    }
                    let up = m3.services.filter(\.up).count
                    StatusCard(title: "Service health", value: m3.services.isEmpty ? "Checking…" : "\(up) / \(m3.services.count) up", detail: m3.services.filter { !$0.up }.map(\.name).joined(separator: ", ").ifEmpty("All answering"), icon: "stethoscope", tone: m3.services.isEmpty ? .neutral : up == m3.services.count ? .good : .warn)
                    StatusCard(title: "Approvals", value: "\(m3.pending.count) waiting", detail: "Touch ID + JEV to approve; deny is final", icon: "touchid", tone: m3.pending.isEmpty ? .good : .warn)
                    StatusCard(title: "Backend", value: m3.backendPort.map { "127.0.0.1:\($0)" } ?? "Off", detail: "Read-only: /health, /api/inbox, /api/services", icon: "server.rack", tone: m3.backendPort == nil ? .warn : .good)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Skill search").font(.title2.bold())
                    TextField("Search \(m3.skills.count) local skills + \(rea.count) REA skills", text: $q).textFieldStyle(.roundedBorder)
                    let local = SkillIndex.search(q, in: m3.skills).prefix(12)
                    let reaHits = rea.filter { q.isEmpty || $0.localizedCaseInsensitiveContains(q) }.prefix(6)
                    ForEach(Array(reaHits), id: \.self) { n in Label(n, systemImage: "bolt.horizontal").font(.callout.monospaced()) }
                    ForEach(Array(local)) { s in
                        VStack(alignment: .leading) { Text(s.name).font(.callout.weight(.semibold)); Text(s.summary).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                    }
                }
            }.padding(24)
        }
        .task {
            await m3.checkHealth()
            rea = (await JarvisClient.get(JarvisEndpoint.fromDefaults().runtime("/api/rea/skills"), as: ReaSkills.self)).value?.tools.map(\.name) ?? []
        }
    }
}

extension String { func ifEmpty(_ d: String) -> String { isEmpty ? d : self } }

/// Dev-only: CONSOLE_SNAPSHOT=/path.png renders this app's own window to PNG and quits
/// (no Screen Recording permission needed; captures nothing outside the app).
@MainActor enum WindowSnapshot {
    static func scheduleIfRequested() {
        guard let out = ProcessInfo.processInfo.environment["CONSOLE_SNAPSHOT"], !out.isEmpty else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
            if let v = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil })?.contentView,
               let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) {
                v.cacheDisplay(in: v.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: out))
            }
            NSApp.terminate(nil)
        }
    }
}

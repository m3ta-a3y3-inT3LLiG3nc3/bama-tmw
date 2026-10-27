import SwiftUI
import ConsoleCore

/// JARVIS desktop → BAMAMac native screens. All reads go through ReaMcpClient (127.0.0.1:9783/mcp) or 9782 GETs.
/// Writes are never sent from here except the coach's own Approve/Deny click (Touch ID for approve, once only).
@MainActor @Observable final class JarvisHub {
    let rea = ReaMcpClient.mac()
    let ep = JarvisEndpoint.fromDefaults()
    var status: JarvisStatus?
    var stack: BamaStack?
    var tools: [McpTool] = []
    var error: String?
    let inbox: ApprovalInbox
    init() {
        let r = ReaMcpClient.mac(), e = JarvisEndpoint.fromDefaults()
        let api: any ApprovalsAPI = ProcessInfo.processInfo.environment["CONSOLE_DEMO"] == "1" ? DemoApprovalsAPI() : ReaApprovalsAPI(rea: r, runtimeBase: e.runtime(""))
        inbox = ApprovalInbox(api: api, auth: TouchIDAuth())
    }
    func refresh() async {
        status = await JarvisClient.status(ep)
        stack = await JarvisClient.get(ep.runtime("/api/bama/stack"), as: BamaStack.self, timeout: 6).value
        do { tools = try await rea.listTools(); error = nil } catch { self.error = error.localizedDescription }
        await inbox.refresh()
    }
}

struct HUDView: View {
    @Environment(JarvisHub.self) var hub
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 20) {
            SectionHeader(title: "JARVIS HUD", subtitle: "Native port of the JARVIS desktop · loopback only · rea-mcp gateway", icon: "circle.hexagongrid")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200))], spacing: 12) {
                StatusCard(title: "Agent runtime :9782", value: hub.status?.runtimeUp == true ? "Up" : "Down", detail: hub.status?.runtime.value?.copilot ?? "—", icon: "cpu", tone: hub.status?.runtimeUp == true ? .good : .bad)
                StatusCard(title: "rea-mcp :9783", value: hub.status?.reaUp == true ? "Up" : "Down", detail: "\(hub.tools.count) MCP tools", icon: "point.3.connected.trianglepath.dotted", tone: hub.status?.reaUp == true ? .good : .bad)
                StatusCard(title: "Approvals", value: "\(hub.inbox.items.count)", detail: "waiting on you", icon: "checkmark.shield", tone: hub.inbox.items.isEmpty ? .good : .warn)
                StatusCard(title: "Stack", value: hub.stack.map { "\($0.upCount)/\($0.services.count)" } ?? "—", detail: "services up", icon: "server.rack", tone: hub.stack.map { $0.upCount == $0.services.count ? .good : .warn } ?? .neutral)
            }
            if let e = hub.error { Label(e, systemImage: "exclamationmark.triangle").foregroundStyle(Color.statusWarn) }
            Button("Refresh") { Task { await hub.refresh() } }.buttonStyle(.glass)
        }.padding(24) }
    }
}

struct ReaApprovalsView: View {
    @Environment(JarvisHub.self) var hub
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "rea-mcp Approvals", subtitle: "rea_approvals_list · approve runs exactly once (Touch ID) · deny never runs · nothing auto-approves", icon: "checkmark.shield")
            if let e = hub.inbox.lastError { Text(e).foregroundStyle(Color.statusWarn) }
            if hub.inbox.items.isEmpty { ContentUnavailableView("Inbox clear", systemImage: "tray", description: Text("No held rea-mcp actions.")) }
            ForEach(hub.inbox.items) { a in
                GlassCard { HStack {
                    VStack(alignment: .leading) { Text(a.summary).font(.headline); Text("\(a.id) · \(a.date.formatted())").font(.caption.monospaced()).foregroundStyle(.secondary) }
                    Spacer()
                    Button("Deny", role: .destructive) { Task { await hub.inbox.decide(a.id, .deny) } }.buttonStyle(.glass)
                    Button { Task { await hub.inbox.decide(a.id, .approve) } } label: { Label("Approve with Touch ID", systemImage: "touchid") }.buttonStyle(.glassProminent)
                } }
            }
            Button("Refresh") { Task { await hub.inbox.refresh() } }
        }.padding(24) }.task { await hub.inbox.refresh() }
    }
}

struct StackHealthView: View {
    @Environment(JarvisHub.self) var hub
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Health", subtitle: "GET /api/bama/stack on 9782 · read only", icon: "waveform.path.ecg")
            if let s = hub.stack {
                ForEach(s.sorted, id: \.name) { r in
                    LabeledContent { Text([r.svc.status, r.svc.code.map { "HTTP \($0)" }, r.svc.ms.map { "\($0) ms" }, r.svc.action].compactMap { $0 }.joined(separator: " · ")).foregroundStyle(r.svc.status == "up" ? Color.statusGood : Color.statusBad).monospaced() } label: { Label(r.name, systemImage: r.svc.status == "up" ? "checkmark.circle.fill" : "xmark.octagon.fill") }
                    Divider()
                }
            } else { ContentUnavailableView("Stack unavailable", systemImage: "server.rack", description: Text("9782 did not answer /api/bama/stack")) }
        }.padding(24) }
    }
}

struct SkillsSearchView: View {
    @Environment(JarvisHub.self) var hub
    @State private var q = "orbit"; @State private var hits: [ReaSkill] = []; @State private var hub2: [String] = []; @State private var err: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Skills", subtitle: "rea_skills_search · falls back to ~/m3ta-os/hub/skills/INDEX.md · read only", icon: "books.vertical")
            TextField("Search skills", text: $q).textFieldStyle(.roundedBorder).onSubmit { Task { await run() } }
            if let err { Text(err).font(.caption).foregroundStyle(Color.statusWarn) }
            List {
                ForEach(hits) { s in VStack(alignment: .leading) { HStack { Text(s.id).font(.headline.monospaced()); if s.writes == true { Text("gated").font(.caption).foregroundStyle(Color.statusWarn) } }; Text(s.description).font(.caption).foregroundStyle(.secondary).lineLimit(2) } }
                ForEach(hub2, id: \.self) { Text($0).font(.callout) }
            }
        }.padding(24).task { await run() }
    }
    func run() async {
        do { hits = try await hub.rea.searchSkills(q); hub2 = []; err = nil }
        catch { hits = []; err = "rea-mcp: \(error.localizedDescription) — showing hub index"; hub2 = HubSkillIndex.search(q, in: HubSkillIndex.parse((try? String(contentsOfFile: HubSkillIndex.path, encoding: .utf8)) ?? "")) }
    }
}

struct OrbitPanelView: View {
    @Environment(JarvisHub.self) var hub
    @State private var op = "status"; @State private var out = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Orbit", subtitle: "rea_orbit_* read tools only · writes need approval", icon: "globe.americas")
            Picker("Read", selection: $op) { ForEach(ConsoleCommand.orbitReads, id: \.self) { Text($0) } }.pickerStyle(.segmented)
            ScrollView { Text(out).font(.caption.monospaced()).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                .padding().glassEffect(.regular, in: .rect(cornerRadius: 16))
        }.padding(24).task(id: op) { out = await ChatModel.run(hub.rea, "rea_orbit_\(op)", [:]) }
    }
}

@MainActor @Observable final class ChatModel {
    struct Msg: Identifiable { let id = UUID(); let me: Bool; let text: String }
    var msgs: [Msg] = [.init(me: false, text: "JARVIS chat (native). /orbit, /skills, /brains run read tools through rea-mcp. Free-form chat with m3tahu3man is TODO (needs the CopilotKit AG-UI stream from 9782).")]
    static func run(_ rea: ReaMcpClient, _ tool: String, _ args: [String: String]) async -> String {
        do {
            let r = try await rea.callRead(tool, args)
            let d = try JSONSerialization.data(withJSONObject: r["output"] ?? r, options: [.prettyPrinted, .sortedKeys])
            return String(decoding: d, as: UTF8.self).prefix(6000).description
        } catch { return "Error: \(error.localizedDescription)" }
    }
    func send(_ text: String, rea: ReaMcpClient) async {
        msgs.append(.init(me: true, text: text))
        switch ConsoleCommand.parse(text) {
        case .read(let t, let a): msgs.append(.init(me: false, text: "\(t)\n" + (await Self.run(rea, t, a))))
        case .needsApproval(let why): msgs.append(.init(me: false, text: "Held: \(why). Nothing was sent."))
        // TODO(jarvis-merge P3): stream to 9782 /api/copilotkit-intel (agent m3tahu3man, AG-UI protocol) — not a simple REST call.
        case .chat: msgs.append(.init(me: false, text: "Free-form chat isn't wired yet (TODO: CopilotKit m3tahu3man). Use JARVIS for chat for now, or try /orbit agents."))
        }
    }
}

struct JarvisChatView: View {
    @Environment(JarvisHub.self) var hub
    @State private var m = ChatModel(); @State private var draft = ""
    var body: some View {
        VStack(alignment: .leading) {
            SectionHeader(title: "Chat", subtitle: "m3tahu3man · /orbit /skills /brains via rea-mcp", icon: "bubble.left.and.text.bubble.right")
            ScrollView { VStack(alignment: .leading, spacing: 8) { ForEach(m.msgs) { x in
                Text(x.text).font(x.me ? .body : .callout.monospaced()).padding(10).frame(maxWidth: 640, alignment: .leading)
                    .background(x.me ? Color.m3taGold.opacity(0.18) : Color.secondary.opacity(0.1), in: .rect(cornerRadius: 12))
                    .frame(maxWidth: .infinity, alignment: x.me ? .trailing : .leading)
            } } }
            HStack { TextField("Message or /orbit agents", text: $draft).textFieldStyle(.roundedBorder).onSubmit(send); Button("Send", action: send).buttonStyle(.glassProminent) }
        }.padding(24)
    }
    func send() { let t = draft; draft = ""; guard !t.isEmpty else { return }; Task { await m.send(t, rea: hub.rea) } }
}

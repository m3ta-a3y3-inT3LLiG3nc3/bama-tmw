import SwiftUI
import ConsoleCore

/// App Mesh (t1087u): read-only. Health from 9782 /api/bama/stack + loopback GETs; mapping from the hub.
/// Fix/Restart only queues an approval item (rea-mcp records it as a manual step) — nothing is restarted from here.
@MainActor @Observable final class AppMeshHub {
    var entries: [AppMeshEntry] = []
    var model: String?
    var mapState = "loading"
    var stack: BamaStack?
    var probes: [Int: Bool] = [:]
    var message: String?
    let hub = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("m3ta-os/hub")
    func refresh() async {
        let map = try? String(contentsOf: hub.appendingPathComponent("agents/APP-MAP.md"), encoding: .utf8)
        let idx = [ "INDEX.md", "skills/INDEX.md", "agents/INDEX.md" ].compactMap { try? String(contentsOf: hub.appendingPathComponent($0), encoding: .utf8) }.joined(separator: "\n")
        let p: (entries: [AppMeshEntry], model: String?) = map.map { AppMesh.parse($0) } ?? (entries: [], model: nil)
        mapState = map == nil ? "pending — APP-MAP.md missing" : (p.entries.isEmpty ? "pending — APP-MAP.md has no table yet" : "\(p.entries.count) apps from APP-MAP.md")
        model = p.model
        entries = AppMesh.merged(p.entries, model: p.model).map { var e = $0; e.skills = AppMesh.skills(for: e, index: idx); return e }
        stack = await JarvisClient.get(JarvisEndpoint.fromDefaults().runtime("/api/bama/stack"), as: BamaStack.self, timeout: 6).value
        var pr: [Int: Bool] = [:]
        for port in Set(entries.flatMap(\.ports)) { pr[port] = await AppMesh.probe(port) }
        probes = pr
    }
    func queueFix(_ e: AppMeshEntry) async {
        let svc = AppMesh.services(for: e, in: stack).first { $0.1.status != "up" }?.0 ?? e.slug
        do { let id = try await ReaMcpClient.mac().queueRestart(svc); message = "Queued for your approval: restart \(svc) (\(id)). Approving records a manual step; nothing restarts on its own." }
        catch { message = "Could not queue: \(error.localizedDescription)" }
    }
}

struct AppMeshView: View {
    @State private var m = AppMeshHub()
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "App Mesh", subtitle: "Read-only · health, MCP connections, agents, skills, models per app · fixes queue for approval", icon: "point.3.filled.connected.trianglepath.dotted")
            HStack { Label(m.mapState, systemImage: "doc.text"); if let md = m.model { Label(md, systemImage: "cpu") } }.font(.callout).foregroundStyle(.secondary)
            if let msg = m.message { Label(msg, systemImage: "hourglass").foregroundStyle(Color.m3taGold) }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), alignment: .top)], spacing: 12) {
                ForEach(m.entries) { e in
                    let svcs = AppMesh.services(for: e, in: m.stack)
                    let h = AppMesh.health(e, services: svcs, probes: m.probes)
                    GlassCard { VStack(alignment: .leading, spacing: 6) {
                        HStack { Text(e.app).font(.title3.weight(.semibold)); Spacer()
                            Text(h.label).font(.caption.weight(.bold)).padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Capsule().fill(h == .up ? Color.statusGood.opacity(0.25) : h == .pending || h == .unknown ? Color.gray.opacity(0.25) : Color.statusWarn.opacity(0.25))) }
                        Text(e.portNote.isEmpty ? "—" : e.portNote).font(.caption.monospaced()).foregroundStyle(.secondary)
                        if !e.ports.isEmpty { Text(e.ports.map { "\($0) \(m.probes[$0] == true ? "✓" : "✗")" }.joined(separator: "  ")).font(.caption.monospaced()) }
                        if !svcs.isEmpty { Text(svcs.map { "\($0.0): \($0.1.status)" }.joined(separator: " · ")).font(.caption) }
                        row("MCP", e.mcp); row("Agents", e.agents); row("Skills", e.skills.isEmpty ? ["pending"] : e.skills)
                        row("Model", [e.model ?? "pending"])
                        if h == .down || h == .partial { Button("Queue fix / restart", systemImage: "hourglass") { Task { await m.queueFix(e) } }.buttonStyle(.glass) }
                    } }
                }
            }
            Button("Refresh") { Task { await m.refresh() } }.buttonStyle(.glass)
        }.padding(24) }.task { await m.refresh() }
    }
    func row(_ k: String, _ v: [String]) -> some View {
        HStack(alignment: .firstTextBaseline) { Text(k).font(.caption.weight(.semibold)).frame(width: 52, alignment: .leading); Text(v.isEmpty ? "—" : v.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary) }
    }
}

import Testing
import Foundation
@testable import ConsoleCore

@Suite struct AppMeshTests {
    let md = """
    # App map
    Default model everywhere: Ollama 127.0.0.1:11434 `m3ta/qwen3-8b`. Other.

    | App | Port | Agents | MCP |
    |---|---|---|---|
    | OpenDuet | 3010 app (stack 53363/53368 down) | LangGraph, Knowledge → Hermes, QB | rea-mcp (13 reads), +linear (OAuth) |
    | OpenDots | 4310 / 4320 | Instinct, Grok Bot | rea-mcp, linear |
    | Plane | not found on Mac, no key | QB | pending instance + key |
    | broken row
    | | 1 | x | y |
    Trailing text
    """
    @Test func parsesTableDefensively() {
        let (e, model) = AppMesh.parse(md)
        #expect(model == "m3ta/qwen3-8b")
        #expect(e.map(\.app) == ["OpenDuet", "OpenDots", "Plane"])
        #expect(e[0].ports == [3010] && e[0].agents == ["LangGraph", "Knowledge", "Hermes", "QB"])
        #expect(e[1].ports == [4310, 4320] && e[1].mcp == ["rea-mcp", "linear"])
        #expect(e[2].pending && e[2].ports.isEmpty)
        #expect(AppMesh.parse("").entries.isEmpty && AppMesh.parse("no table here").model == nil)
    }
    @Test func mergeAddsPendingExpectedApps() {
        let m = AppMesh.merged(AppMesh.parse(md).entries, model: nil)
        for n in ["OpenBot", "OpenMuse", "CopilotKit runtime", "Paperclip", "Linear", "AionUi"] { #expect(m.contains { $0.app == n && $0.portNote.hasPrefix("pending") }, "\(n)") }
        #expect(m.filter { $0.app.hasPrefix("OpenDuet") }.count == 1)
    }
    @Test func skillsServicesHealth() throws {
        let e = AppMesh.parse(md).entries[1]
        let idx = "- [~/.instinct/skills](z) instinct\n- [instinct-ops](x.md) — Instinct desk\n| `grok-routing` | Grok Bot |\n- [other](y.md)"
        #expect(AppMesh.skills(for: e, index: idx) == ["instinct-ops", "grok-routing"])
        let stack = try JSONDecoder().decode(BamaStack.self, from: Data(#"{"services":{"opendots":{"status":"up"},"opendots-api":{"status":"down"},"openmuse":{"status":"up"}}}"#.utf8))
        let s = AppMesh.services(for: e, in: stack)
        #expect(s.map(\.0) == ["opendots", "opendots-api"])
        #expect(AppMesh.health(e, services: s, probes: [4310: true]) == .partial)
        #expect(AppMesh.health(e, services: [], probes: [4310: true, 4320: true]) == .up)
        #expect(AppMesh.health(AppMesh.parse(md).entries[2], services: [], probes: [:]) == .pending)
    }
    @Test func restartOnlyQueues() async throws {
        let t = FakeTransport(); t.responses["/approvals/hold"] = (#"{"id":"ap-9","status":"pending"}"#, 200)
        let c = ReaMcpClient.mac(transport: t)
        #expect(try await c.queueRestart("openbot-tmw") == "ap-9")
        #expect(t.calls.last?.0.absoluteString == "http://127.0.0.1:9783/approvals/hold" && t.calls.last!.1.contains("supervisor.restart:openbot-tmw"))
        await #expect(throws: ReaMcpError.notLoopback) { try await c.queueRestart("rm -rf") }
    }
}

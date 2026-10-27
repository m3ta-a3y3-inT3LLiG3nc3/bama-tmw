import Testing
import Foundation
@testable import ConsoleCore

@Suite struct JarvisMergeTests {
    @Test func stackDecodes() throws {
        let s = try JSONDecoder().decode(BamaStack.self, from: Data(#"{"services":{"rea-mcp":{"status":"up","code":200,"ms":1},"openbot-tmw":{"status":"down","action":"escalated"}},"config":{}}"#.utf8))
        #expect(s.upCount == 1); #expect(s.sorted.first?.name == "openbot-tmw")
    }
    @Test func commandsMapToReadTools() {
        #expect(ConsoleCommand.parse("/orbit") == .read(tool: "rea_orbit_status", args: [:]))
        #expect(ConsoleCommand.parse("/orbit agents") == .read(tool: "rea_orbit_agents", args: [:]))
        #expect(ConsoleCommand.parse("/skills orbit mesh") == .read(tool: "rea_skills_search", args: ["q": "orbit mesh"]))
        #expect(ConsoleCommand.parse("/skills get agents:orbit") == .read(tool: "rea_skills_get", args: ["id": "agents:orbit"]))
        #expect(ConsoleCommand.parse("/brains status") == .read(tool: "rea_brains_status", args: [:]))
        #expect(ConsoleCommand.parse("hello") == .chat("hello"))
    }
    @Test func writeCommandsNeverRead() {
        for c in ["/orbit message hi", "/orbit upsert_row", "/skills run agents:gws-gmail-send"] {
            if case .needsApproval = ConsoleCommand.parse(c) {} else { Issue.record("\(c) not gated") }
        }
        // every read mapping is on the client allowlist
        for c in ["/orbit status", "/orbit tasks", "/skills x", "/skills", "/brains q"] {
            if case .read(let t, _) = ConsoleCommand.parse(c) { #expect(ReaMcpClient.readTools.contains(t)) }
        }
    }
    @Test func hubIndexParses() {
        let l = HubSkillIndex.parse("# Skills\n- `orbit` — mesh\n| name | desc |\n|---|---|\n| grok | x |\n")
        #expect(HubSkillIndex.search("orbit", in: l).count == 1)
    }
}

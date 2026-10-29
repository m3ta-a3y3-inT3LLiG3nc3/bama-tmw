import Testing
import Foundation
@testable import ConsoleCore

@Suite struct BotMapTests {
    let m = try! BotMapLoader.loadBundled()
    @Test func decodesCounts() {
        #expect(m.bots.count == 35)
        #expect(m.counts.openbot_bots == 35)
        #expect(m.counts.orbit_agents == 274)
        #expect(m.counts.grokbot_agents == 56)
    }
    @Test func bridgeMapsToOrbitAndGrok() {
        let g = m.bots.first { $0.openbot.name == "Grokbot bridge" }!
        #expect(g.orbit.first?.external_id == "hermes-profile-grokbot-bridge")
        #expect(g.grokbot?.name == "GROK-M3ta-BOT")
    }
    @Test func notionConflictFlagged() {
        let n = m.bots.first { $0.openbot.name == "Notion bridge" }!
        #expect(n.flags.contains("conflict:registry-retired-vs-active"))
        #expect(BotFilter.conflicts.matches(n))
    }
    @Test func searchAndFilter() {
        #expect(m.filtered(query: "", filter: .all).count == 35)
        #expect(m.filtered(query: "orbit", filter: .bridges).allSatisfy { $0.status == "bridge" })
        #expect(m.filtered(query: "qu3bii", filter: .all).count >= 3)
        #expect(m.filtered(query: "zzz-none", filter: .all).isEmpty)
        #expect(m.filtered(query: "", filter: .noBrain).count == 35)
    }
    @Test func brainUnknownWhenMissing() throws {
        let j = #"{"generated":"x","counts":{"openbot_bots":1,"orbit_agents":0,"grokbot_agents":0,"mapped_to_orbit":0,"mapped_to_grokbot":0,"brain_wired":0},"conflicts":[],"bots":[{"openbot":{"id":"a","name":"A"},"role":"r","orbit":[],"status":"template","flags":[]}]}"#
        let b = try BotMapLoader.decode(Data(j.utf8)).bots[0]
        #expect(b.brainWired == nil)
        #expect(BotFilter.gaps.matches(b))
    }
}

@Suite struct BrainClientTests {
    @Test func parsesSearchTimeout() {
        let d = #"{"jsonrpc":"2.0","id":1,"result":{"structuredContent":{"ok":true,"output":{"status":"vault unavailable: timed out","results":[]}}}}"#
        #expect(BrainClient.parseSearch(Data(d.utf8)) == .results(status: "vault unavailable: timed out", hits: []))
    }
    @Test func parsesSearchHits() {
        let d = #"{"result":{"structuredContent":{"output":{"status":"ok","results":[{"path":"Meetings/a.md","snippet":"orbit mesh"}]}}}}"#
        guard case .results(_, let h) = BrainClient.parseSearch(Data(d.utf8)) else { Issue.record("no"); return }
        #expect(h == [.init(path: "Meetings/a.md", snippet: "orbit mesh")])
    }
    @Test func parsesStatus() {
        let d = #"{"result":{"structuredContent":{"output":{"obsidian":{"status":"read-only (local files)"},"mem":{"status":"needs connection"}}}}}"#
        #expect(BrainClient.parseStatus(Data(d.utf8)) == .online(["obsidian": "read-only (local files)", "mem": "needs connection"]))
    }
    @Test func loopbackOnly() {
        #expect(BrainClient.mcpURL.host == "127.0.0.1")
        #expect(JarvisEndpoint().runtime("/health").host == "127.0.0.1")
        #expect(String(data: BrainClient.body(tool: "rea_brains_search", args: ["q": "x"]), encoding: .utf8)!.contains("rea_brains_search"))
    }
}

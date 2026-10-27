import Testing
import Foundation
@testable import ConsoleCore

@Suite struct JarvisClientTests {
    @Test func decodesRuntimeHealth() {
        let d = #"{"ok":true,"service":"agent-runtime","mcp":true,"copilotRuntime":"available","copilot":"mounted (v2 1.77.0)"}"#.data(using: .utf8)!
        let p = JarvisClient.decode(d, status: 200, as: RuntimeHealth.self)
        #expect(p.value?.ok == true); #expect(p.value?.mcp == true)
    }
    @Test func decodesReaHealth() {
        let d = #"{"ok":true,"service":"rea-mcp","skills":20,"extensions":22,"pending":8}"#.data(using: .utf8)!
        #expect(JarvisClient.decode(d, status: 200, as: ReaHealth.self).value?.skills == 20)
    }
    @Test func decodesSkills() {
        let d = #"{"tools":[{"name":"rea_router","title":"x","inputSchema":{}}]}"#.data(using: .utf8)!
        #expect(JarvisClient.decode(d, status: 200, as: ReaSkills.self).value?.tools.first?.name == "rea_router")
    }
    @Test func non200IsOfflineNotReachable() {
        // Old heuristic counted 404/403 as reachable; now only 200 + decodable health counts.
        let d = #"{"error":"not found"}"#.data(using: .utf8)!
        #expect(JarvisClient.decode(d, status: 404, as: RuntimeHealth.self) == .offline("HTTP 404"))
        #expect(JarvisClient.decode(Data("<html>".utf8), status: 200, as: RuntimeHealth.self) == .offline("unexpected response"))
    }
    @Test func endpointIsLoopbackAndValidated() {
        let e = JarvisEndpoint(runtimePort: 1, reaPort: 2)
        #expect(e.runtime("/health").absoluteString == "http://127.0.0.1:1/health")
        #expect(e.rea("/health").host == "127.0.0.1")
        #expect(!JarvisEndpoint.validPort(0)); #expect(!JarvisEndpoint.validPort(70000))
        let d = UserDefaults(suiteName: "jarvis-test-\(UUID())")!
        d.set(0, forKey: "jarvisRuntimePort")
        #expect(JarvisEndpoint.fromDefaults(d) == JarvisEndpoint())
    }
    @Test func closedLoopbackPortShowsOffline() async {
        // Bind-free: pick a port nothing listens on and confirm both probes go offline.
        let s = await JarvisClient.status(JarvisEndpoint(runtimePort: 9, reaPort: 9))
        #expect(s.fullyOffline)
        #expect(await CopilotHealth.check(JarvisEndpoint(runtimePort: 9, reaPort: 9)) != .online(200))
    }
}

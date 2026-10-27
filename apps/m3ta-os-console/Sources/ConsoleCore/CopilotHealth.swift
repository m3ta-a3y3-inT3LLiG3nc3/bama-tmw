import Foundation

/// S-007 health: GET agent-runtime /health (real health route, needs 200 + ok:true). Never starts or restarts anything.
public enum CopilotHealth {
    public enum Result: Sendable, Equatable { case online(Int), offline(String) }
    public static func check(_ e: JarvisEndpoint = .fromDefaults(), timeout: TimeInterval = 2) async -> Result {
        switch await JarvisClient.get(e.runtime("/health"), as: RuntimeHealth.self, timeout: timeout) {
        case .ok(let h): return h.ok ? .online(200) : .offline("health ok=false")
        case .offline(let why): return .offline(why)
        }
    }
}

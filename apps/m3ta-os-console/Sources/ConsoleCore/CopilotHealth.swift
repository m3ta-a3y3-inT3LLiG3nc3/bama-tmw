import Foundation

/// S-007 stub: read-only GET to JARVIS's runtime on loopback. Never starts or restarts anything.
public enum CopilotHealth {
    public static let host = "127.0.0.1"
    public static let port = 9782
    public static var url: URL { URL(string: "http://\(host):\(port)/api/copilotkit")! }

    public enum Result: Sendable, Equatable { case online(Int), offline(String) }

    public static func check(timeout: TimeInterval = 2) async -> Result {
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        req.httpMethod = "GET"
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = timeout
        cfg.connectionProxyDictionary = [:]
        do {
            let (_, resp) = try await URLSession(configuration: cfg).data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            return code > 0 && code < 500 ? .online(code) : .offline("HTTP \(code)")
        } catch {
            return .offline(error.localizedDescription)
        }
    }
}

import Foundation

/// Read-only client for the MetaOS brain via JARVIS's rea-mcp on loopback (rea_brains_status / rea_brains_search).
/// Never starts or restarts JARVIS; never writes.
public enum BrainClient {
    public static let host = "127.0.0.1"
    public static let port = 9783
    public static var mcpURL: URL { URL(string: "http://\(host):\(port)/mcp")! }

    public struct Hit: Sendable, Equatable, Identifiable { public let path: String; public let snippet: String; public var id: String { path + snippet } }
    public enum Outcome: Sendable, Equatable { case results(status: String, hits: [Hit]), offline(String) }
    public enum StatusOutcome: Sendable, Equatable { case online([String: String]), offline(String) }

    public static func body(tool: String, args: [String: String]) -> Data {
        let o: [String: Any] = ["jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": ["name": tool, "arguments": args]]
        return try! JSONSerialization.data(withJSONObject: o)
    }

    /// Pull `result.structuredContent.output` out of a JSON-RPC reply.
    static func output(_ d: Data) -> [String: Any]? {
        guard let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let r = j["result"] as? [String: Any], let sc = r["structuredContent"] as? [String: Any] else { return nil }
        return sc["output"] as? [String: Any]
    }

    public static func parseSearch(_ d: Data) -> Outcome {
        guard let out = output(d) else { return .offline("unexpected reply") }
        let status = out["status"] as? String ?? "unknown"
        let hits = (out["results"] as? [[String: Any]] ?? []).map { h in
            Hit(path: (h["path"] ?? h["file"] ?? h["title"]) as? String ?? "?", snippet: (h["snippet"] ?? h["line"] ?? h["text"]) as? String ?? "")
        }
        return .results(status: status, hits: hits)
    }

    public static func parseStatus(_ d: Data) -> StatusOutcome {
        guard let out = output(d) else { return .offline("unexpected reply") }
        var m: [String: String] = [:]
        for (k, v) in out { m[k] = ((v as? [String: Any])?["status"] as? String) ?? "unknown" }
        return .online(m)
    }

    static func post(_ tool: String, _ args: [String: String], timeout: TimeInterval) async throws -> Data {
        var req = URLRequest(url: mcpURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        req.httpMethod = "POST"; req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = body(tool: tool, args: args)
        let cfg = URLSessionConfiguration.ephemeral; cfg.timeoutIntervalForRequest = timeout; cfg.connectionProxyDictionary = [:]
        let (d, _) = try await URLSession(configuration: cfg).data(for: req)
        return d
    }

    public static func status(timeout: TimeInterval = 4) async -> StatusOutcome {
        do { return parseStatus(try await post("rea_brains_status", [:], timeout: timeout)) } catch { return .offline(error.localizedDescription) }
    }
    public static func search(_ q: String, source: String = "vault", timeout: TimeInterval = 15) async -> Outcome {
        do { return parseSearch(try await post("rea_brains_search", ["q": q, "source": source], timeout: timeout)) } catch { return .offline(error.localizedDescription) }
    }
}

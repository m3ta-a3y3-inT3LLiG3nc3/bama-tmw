import Foundation

/// M2: read-only client for JARVIS's EXISTING loopback routes.
///  - agent-runtime (default 9782): GET /health, GET /api/models, GET /api/rea/skills
///  - rea-mcp       (default 9783): GET /health
/// Only GETs. Never starts, stops or restarts JARVIS. Host is forced to loopback.
public struct JarvisEndpoint: Sendable, Equatable {
    public var runtimePort: Int
    public var reaPort: Int
    public init(runtimePort: Int = 9782, reaPort: Int = 9783) { self.runtimePort = runtimePort; self.reaPort = reaPort }
    public static let host = "127.0.0.1"
    public static func validPort(_ p: Int) -> Bool { (1...65535).contains(p) }
    public func runtime(_ path: String) -> URL { URL(string: "http://\(Self.host):\(runtimePort)\(path)")! }
    public func rea(_ path: String) -> URL { URL(string: "http://\(Self.host):\(reaPort)\(path)")! }
    /// Reads Settings (UserDefaults) with defaults; invalid ports fall back.
    public static func fromDefaults(_ d: UserDefaults = .standard) -> JarvisEndpoint {
        let r = d.integer(forKey: "jarvisRuntimePort"), m = d.integer(forKey: "jarvisReaPort")
        return JarvisEndpoint(runtimePort: validPort(r) ? r : 9782, reaPort: validPort(m) ? m : 9783)
    }
}

public struct RuntimeHealth: Decodable, Sendable, Equatable {
    public let ok: Bool; public let service: String; public let mcp: Bool?
    public let copilotRuntime: String?; public let copilot: String?
}
public struct ReaHealth: Decodable, Sendable, Equatable {
    public let ok: Bool; public let service: String
    public let skills: Int?; public let extensions: Int?; public let pending: Int?
}
public struct ReaSkills: Decodable, Sendable, Equatable {
    public struct Tool: Decodable, Sendable, Equatable { public let name: String; public let title: String? }
    public let tools: [Tool]
}

public enum Probe<T: Sendable & Equatable>: Sendable, Equatable {
    case ok(T), offline(String)
    public var value: T? { if case .ok(let v) = self { v } else { nil } }
}

public struct JarvisStatus: Sendable, Equatable {
    public let runtime: Probe<RuntimeHealth>
    public let rea: Probe<ReaHealth>
    public let models: Probe<ModelRoute>
    public let skills: Probe<ReaSkills>
    public let checkedAt: Date
    /// Healthy = both /health routes answered 200 with ok:true (not "any HTTP < 500").
    public var runtimeUp: Bool { runtime.value?.ok == true }
    public var reaUp: Bool { rea.value?.ok == true }
    public var fullyOffline: Bool { !runtimeUp && !reaUp }
}

public enum JarvisClient {
    static func session(_ t: TimeInterval) -> URLSession {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = t; c.connectionProxyDictionary = [:]
        return URLSession(configuration: c)
    }
    /// GET + require 200 + decode. Anything else is offline with a reason.
    public static func get<T: Decodable & Sendable & Equatable>(_ url: URL, as: T.Type, timeout: TimeInterval = 2) async -> Probe<T> {
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        req.httpMethod = "GET"
        do {
            let (data, resp) = try await session(timeout).data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            return decode(data, status: code, as: T.self)
        } catch { return .offline(error.localizedDescription) }
    }
    public static func decode<T: Decodable & Sendable & Equatable>(_ data: Data, status: Int, as: T.Type) -> Probe<T> {
        guard status == 200 else { return .offline("HTTP \(status)") }
        do { return .ok(try JSONDecoder().decode(T.self, from: data)) } catch { return .offline("unexpected response") }
    }
    public static func status(_ e: JarvisEndpoint = .fromDefaults()) async -> JarvisStatus {
        async let r = get(e.runtime("/health"), as: RuntimeHealth.self)
        async let m = get(e.rea("/health"), as: ReaHealth.self)
        async let mo = get(e.runtime("/api/models"), as: ModelRoute.self)
        async let s = get(e.runtime("/api/rea/skills"), as: ReaSkills.self)
        return JarvisStatus(runtime: await r, rea: await m, models: await mo, skills: await s, checkedAt: Date())
    }
}

import Foundation

/// Read-only view of JARVIS model routing (GET 127.0.0.1:9782/api/models). Never changes toggles, never holds keys.
public struct ModelRoute: Decodable, Sendable, Equatable {
    public struct Route: Decodable, Sendable, Equatable { public let provider: String; public let model: String; public let paid: Bool; public let why: String? }
    public struct Toggle: Decodable, Sendable, Equatable { public let provider: String; public let model: String; public let enabled: Bool? }
    public struct Jev: Decodable, Sendable, Equatable { public let daily_usd_cap: Double }
    public let `default`: Route
    public let fallback: String?
    public let toggles: [String: Toggle]
    public let jev: Jev?
    public let metaKeyPresent: Bool?

    public var paidEnabledCount: Int { toggles.values.filter { $0.enabled != false }.count }

    public static var url: URL { URL(string: "http://127.0.0.1:9782/api/models")! }
    public enum Outcome: Sendable, Equatable { case ok(ModelRoute), offline(String) }

    public static func fetch(timeout: TimeInterval = 2) async -> Outcome {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = timeout; cfg.connectionProxyDictionary = [:]
        do {
            let (data, _) = try await URLSession(configuration: cfg).data(from: url)
            return .ok(try JSONDecoder().decode(ModelRoute.self, from: data))
        } catch { return .offline(error.localizedDescription) }
    }
}

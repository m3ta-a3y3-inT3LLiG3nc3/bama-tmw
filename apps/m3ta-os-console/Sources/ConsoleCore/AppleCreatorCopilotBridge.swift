import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Chapter marker data transfer object matching Studio specifications.
public struct ChapterMarkerDTO: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let timestamp: String
    public let seconds: Double
    public let label: String

    public init(id: String = UUID().uuidString, timestamp: String, seconds: Double, label: String) {
        self.id = id
        self.timestamp = timestamp
        self.seconds = seconds
        self.label = label
    }
}

/// Listening port inspection record matching DevKit specifications.
public struct DevPortRecord: Codable, Sendable, Equatable, Identifiable {
    public var id: String { "\(command)-\(pid)-\(port)" }
    public let command: String
    public let pid: Int
    public let port: Int
    public let name: String
}

/// Response from Apple Studio actions on loopback :9782.
public struct AppleStudioResponse: Codable, Sendable, Equatable {
    public let ok: Bool
    public let summary: String?
    public let error: String?
}

/// Response from DevKit port inspector on loopback :9782.
public struct DevPortResponse: Codable, Sendable, Equatable {
    public let ok: Bool
    public let total: Int?
    public let ports: [DevPortRecord]?
    public let error: String?
}

/// Bridge coordinating Apple Design + Creator Suite + Apple DevKit with CopilotKit suite (:9782) and REA-MCP (:9783).
public final class AppleCreatorCopilotBridge: Sendable {
    public let endpoint: JarvisEndpoint
    public let rea: ReaMcpClient
    public let approvalGate: ApprovalGate?

    public init(
        endpoint: JarvisEndpoint = .fromDefaults(),
        rea: ReaMcpClient? = nil,
        approvalGate: ApprovalGate? = nil
    ) {
        self.endpoint = endpoint
        self.rea = rea ?? ReaMcpClient.mac(port: endpoint.reaPort)
        self.approvalGate = approvalGate
    }

    /// POST request helper to the loopback agent-runtime (:9782)
    private func postJSON<T: Decodable & Sendable>(path: String, body: [String: Any]) async throws -> T {
        let url = endpoint.runtime(path)
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8.0)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await JarvisClient.session(8.0).data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 500
            throw ReaMcpError.http(code)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - 1. Apple Studio Controls

    /// Toggles macOS Recording Mode (cleans desktop, hides Dock, activates Focus shortcut)
    public func toggleRecordingMode(enable: Bool) async throws -> AppleStudioResponse {
        try await postJSON(path: "/api/apple/recording-mode", body: ["enable": enable])
    }

    /// Pushes a generated video script into the native glass Teleprompter panel
    public func stageTeleprompter(script: String, title: String = "Tutorial Script") async throws -> AppleStudioResponse {
        try await postJSON(path: "/api/apple/teleprompter", body: ["script": script, "title": title])
    }

    /// Drops YouTube / Vimeo chapter markers into ChapterClock
    public func stageChapters(markers: [ChapterMarkerDTO]) async throws -> AppleStudioResponse {
        let serialized = markers.map { [
            "id": $0.id,
            "timestamp": $0.timestamp,
            "seconds": $0.seconds,
            "label": $0.label
        ] }
        return try await postJSON(path: "/api/apple/chapters", body: ["chapters": serialized])
    }

    // MARK: - 2. Apple DevKit Controls

    /// Inspects all listening TCP ports (filters by service name or port)
    public func inspectPorts(filter: String = "") async throws -> [DevPortRecord] {
        let path = "/api/apple/ports" + (filter.isEmpty ? "" : "?q=\(filter)")
        let url = endpoint.runtime(path)
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 5.0)
        req.httpMethod = "GET"

        let (data, resp) = try await JarvisClient.session(5.0).data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw ReaMcpError.http((resp as? HTTPURLResponse)?.statusCode ?? 500)
        }
        let parsed = try JSONDecoder().decode(DevPortResponse.self, from: data)
        return parsed.ports ?? []
    }

    // MARK: - 3. Sovereign Agency Snapshot Controls

    /// Deploys an Open Sovereign Snapshot (CRM stages, intake forms, voice receptionist prompt) to a sub-account
    public func deploySnapshot(subAccount: String) async throws -> AppleStudioResponse {
        try await postJSON(path: "/api/apple/snapshot", body: [
            "action": "deploy",
            "subAccount": subAccount
        ])
    }

    // MARK: - 4. CreatorKit Gated Pipeline Execution

    /// Queues a CreatorAction through REA-MCP holding for Touch ID / Operator JEV approval
    public func queueCreatorAction(_ action: CreatorAction) async throws -> String {
        try await CreatorQueue(rea: rea).enqueue(action)
    }
}

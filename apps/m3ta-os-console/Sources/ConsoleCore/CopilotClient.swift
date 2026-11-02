import Foundation

/// S-007: chat client for JARVIS's EXISTING CopilotKit runtime on loopback.
/// The console starts no runtime of its own. Chat runs are POSTed as AG-UI
/// runs to the CopilotKit runtime's agent route
/// (/api/copilotkit/agent/default/run on the agent-runtime port) and the
/// streamed events are folded into messages. (The top-level /agui route on
/// the same port is JARVIS's own REA skill dispatcher, not the chat agent;
/// verified live 2026-11-01.) No keys are stored or sent; model routing
/// (local first) and the JEV approval gate for consequential actions live
/// in JARVIS, not here.
public extension JarvisEndpoint {
    /// CopilotKit runtime mount on the agent-runtime (JARVIS's process).
    func copilotkit() -> URL { runtime("/api/copilotkit") }
    /// AG-UI run route for one agent of the CopilotKit runtime ("default"
    /// is the agent the runtime reports in its info route).
    func copilotAgentRun(_ agentId: String = "default") -> URL { runtime("/api/copilotkit/agent/\(agentId)/run") }
    /// JARVIS's own AG-UI dispatcher (REA skill calls), not the chat agent.
    func agui() -> URL { runtime("/agui") }
}

public struct CopilotMessage: Sendable, Equatable, Identifiable {
    public enum Role: String, Sendable, Equatable { case system, user, assistant, tool }
    public let id: String
    public let role: Role
    public var content: String
    public init(id: String, role: Role, content: String) { self.id = id; self.role = role; self.content = content }
}

/// One AG-UI event, reduced to what the panel renders. Unknown event types
/// parse as `.other` and are ignored by the accumulator: the protocol grows
/// additively and an unrecognized event must never break a run.
public enum CopilotEvent: Sendable, Equatable {
    case runStarted(threadId: String?)
    case textStart(messageId: String)
    case textDelta(messageId: String, delta: String)
    case textEnd(messageId: String)
    case toolCallStart(toolCallId: String, name: String)
    case toolCallEnd(toolCallId: String)
    case runFinished
    case runError(String)
    case other(String)

    /// Parse one SSE `data:` payload (the JSON after the `data:` prefix).
    public static func parse(data: Data) -> CopilotEvent? {
        guard let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = j["type"] as? String else { return nil }
        switch type {
        case "RUN_STARTED": return .runStarted(threadId: j["threadId"] as? String)
        case "TEXT_MESSAGE_START": return .textStart(messageId: j["messageId"] as? String ?? "")
        case "TEXT_MESSAGE_CONTENT": return .textDelta(messageId: j["messageId"] as? String ?? "", delta: j["delta"] as? String ?? "")
        case "TEXT_MESSAGE_END": return .textEnd(messageId: j["messageId"] as? String ?? "")
        case "TOOL_CALL_START": return .toolCallStart(toolCallId: j["toolCallId"] as? String ?? "", name: j["toolCallName"] as? String ?? "tool")
        case "TOOL_CALL_END": return .toolCallEnd(toolCallId: j["toolCallId"] as? String ?? "")
        case "RUN_FINISHED": return .runFinished
        case "RUN_ERROR": return .runError(j["message"] as? String ?? "run failed")
        default: return .other(type)
        }
    }

    /// Parse one raw SSE line. Returns nil for keep-alives, event:/id: lines
    /// and the terminal [DONE] marker.
    public static func parse(line: String) -> CopilotEvent? {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("data:") else { return nil }
        let payload = String(t.dropFirst(5)).trimmingCharacters(in: .whitespaces)
        guard !payload.isEmpty, payload != "[DONE]" else { return nil }
        return parse(data: Data(payload.utf8))
    }
}

/// Folds a stream of AG-UI events into panel state. Pure and synchronous so
/// the whole run lifecycle is unit-testable without a server.
public struct CopilotRunAccumulator: Sendable, Equatable {
    public private(set) var messages: [CopilotMessage] = []
    public private(set) var toolActivity: [String] = []
    public private(set) var isRunning = false
    public private(set) var error: String?
    private var openTextId: String?

    public init(seed: [CopilotMessage] = []) { messages = seed }

    /// Append a locally authored message (the user's next turn) and clear any prior run error.
    public mutating func appendUser(_ m: CopilotMessage) {
        messages.append(m); error = nil
    }

    public mutating func fold(_ e: CopilotEvent) {
        switch e {
        case .runStarted:
            isRunning = true; error = nil
        case .textStart(let mid):
            openTextId = mid
            if !messages.contains(where: { $0.id == mid }) {
                messages.append(CopilotMessage(id: mid, role: .assistant, content: ""))
            }
        case .textDelta(let mid, let delta):
            if let i = messages.firstIndex(where: { $0.id == mid }) {
                messages[i].content += delta
            } else {
                openTextId = mid
                messages.append(CopilotMessage(id: mid, role: .assistant, content: delta))
            }
        case .textEnd(let mid):
            if openTextId == mid { openTextId = nil }
        case .toolCallStart(_, let name):
            // Display only. Tool calls execute inside JARVIS; send/spend/delete
            // actions there are held by the JEV approval gate.
            toolActivity.append(name)
        case .toolCallEnd, .other:
            break
        case .runFinished:
            isRunning = false; openTextId = nil
        case .runError(let why):
            isRunning = false; openTextId = nil; error = why
        }
    }

    /// The stream ended without RUN_FINISHED/RUN_ERROR (dropped connection).
    public mutating func streamEnded() {
        if isRunning { isRunning = false; error = error ?? "stream ended early" }
    }
}

public enum CopilotClient {
    /// AG-UI RunAgentInput body. The app sends chat only: no tools of its own,
    /// so nothing local can be invoked by the runtime.
    public static func runBody(threadId: String, runId: String, messages: [CopilotMessage]) -> Data {
        let o: [String: Any] = [
            "threadId": threadId,
            "runId": runId,
            "state": [String: Any](),
            "messages": messages.map { ["id": $0.id, "role": $0.role.rawValue, "content": $0.content] },
            "tools": [Any](),
            "context": [["description": "client", "value": "M3ta-OS Console (native Mac app)"]],
            "forwardedProps": [String: Any](),
        ]
        return try! JSONSerialization.data(withJSONObject: o)
    }

    public enum Failure: Error, Sendable, Equatable { case http(Int), badResponse }

    static func session(_ t: TimeInterval) -> URLSession {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = t; c.connectionProxyDictionary = [:]
        return URLSession(configuration: c)
    }

    /// POST one run to the CopilotKit runtime's agent route and stream its
    /// events. Throws `Failure.http` on a non-200 reply; transport errors
    /// propagate as-is (URLError etc.), which the panel renders as offline.
    /// `agentId` selects the runtime agent ("default" is the chat agent;
    /// EGMReviewClient passes "egm-goldfish" for cold reviews).
    public static func run(_ e: JarvisEndpoint = .fromDefaults(),
                           agentId: String = "default",
                           threadId: String, messages: [CopilotMessage],
                           timeout: TimeInterval = 120) -> AsyncThrowingStream<CopilotEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var req = URLRequest(url: e.copilotAgentRun(agentId), cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
                    req.httpMethod = "POST"
                    req.setValue("application/json", forHTTPHeaderField: "content-type")
                    req.setValue("text/event-stream", forHTTPHeaderField: "accept")
                    req.httpBody = runBody(threadId: threadId, runId: UUID().uuidString, messages: messages)
                    let (bytes, resp) = try await session(timeout).bytes(for: req)
                    guard let http = resp as? HTTPURLResponse else { throw Failure.badResponse }
                    guard http.statusCode == 200 else { throw Failure.http(http.statusCode) }
                    for try await line in bytes.lines {
                        if let ev = CopilotEvent.parse(line: line) { continuation.yield(ev) }
                    }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

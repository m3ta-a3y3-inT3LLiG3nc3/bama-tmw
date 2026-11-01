import Testing
import Foundation
@testable import ConsoleCore

@Suite struct CopilotClientTests {
    @Test func endpointsPointAtJarvisRuntime() {
        let e = JarvisEndpoint(runtimePort: 9782, reaPort: 9783)
        #expect(e.copilotkit().absoluteString == "http://127.0.0.1:9782/api/copilotkit")
        #expect(e.copilotAgentRun().absoluteString == "http://127.0.0.1:9782/api/copilotkit/agent/default/run")
        #expect(e.agui().absoluteString == "http://127.0.0.1:9782/agui")
        #expect(e.copilotAgentRun().host == "127.0.0.1")
    }

    @Test func runBodyCarriesThreadAndMessages() throws {
        let msgs = [CopilotMessage(id: "m1", role: .user, content: "mesh status?")]
        let j = try #require(JSONSerialization.jsonObject(with: CopilotClient.runBody(threadId: "t1", runId: "r1", messages: msgs)) as? [String: Any])
        #expect(j["threadId"] as? String == "t1")
        #expect(j["runId"] as? String == "r1")
        let sent = try #require(j["messages"] as? [[String: Any]])
        #expect(sent.first?["role"] as? String == "user")
        #expect(sent.first?["content"] as? String == "mesh status?")
        // The app exposes no local tools to the runtime.
        #expect((j["tools"] as? [Any])?.isEmpty == true)
    }

    @Test func parsesTextDeltaAndRunError() {
        let d = CopilotEvent.parse(line: #"data: {"type":"TEXT_MESSAGE_CONTENT","messageId":"a1","delta":"Hel"}"#)
        #expect(d == .textDelta(messageId: "a1", delta: "Hel"))
        let err = CopilotEvent.parse(line: #"data: {"type":"RUN_ERROR","message":"boom"}"#)
        #expect(err == .runError("boom"))
        #expect(CopilotEvent.parse(line: "data: [DONE]") == nil)
        #expect(CopilotEvent.parse(line: ": keep-alive") == nil)
        #expect(CopilotEvent.parse(line: #"data: {"type":"STATE_SNAPSHOT","snapshot":{}}"#) == .other("STATE_SNAPSHOT"))
    }

    @Test func accumulatorFoldsDeltasIntoOneAssistantMessage() {
        var a = CopilotRunAccumulator(seed: [CopilotMessage(id: "u1", role: .user, content: "hi")])
        a.fold(.runStarted(threadId: "t"))
        #expect(a.isRunning)
        a.fold(.textStart(messageId: "a1"))
        a.fold(.textDelta(messageId: "a1", delta: "Mesh is "))
        a.fold(.textDelta(messageId: "a1", delta: "live."))
        a.fold(.textEnd(messageId: "a1"))
        a.fold(.toolCallStart(toolCallId: "tc1", name: "rea_router"))
        a.fold(.runFinished)
        #expect(!a.isRunning)
        #expect(a.error == nil)
        #expect(a.messages.count == 2)
        #expect(a.messages.last?.role == .assistant)
        #expect(a.messages.last?.content == "Mesh is live.")
        #expect(a.toolActivity == ["rea_router"])
    }

    @Test func accumulatorRecordsRunError() {
        var a = CopilotRunAccumulator()
        a.fold(.runStarted(threadId: nil))
        a.fold(.runError("model unavailable"))
        #expect(!a.isRunning)
        #expect(a.error == "model unavailable")
    }

    @Test func closedLoopbackPortRunFails() async {
        // Nothing listens on port 9: the run stream must throw, never hang or fake a reply.
        let e = JarvisEndpoint(runtimePort: 9, reaPort: 9)
        var threw = false
        do {
            for try await _ in CopilotClient.run(e, threadId: "t", messages: [CopilotMessage(id: "u", role: .user, content: "hi")], timeout: 3) {}
        } catch { threw = true }
        #expect(threw)
    }
}

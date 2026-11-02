import Testing
import Foundation
@testable import ConsoleCore

@Suite struct EGMReviewTests {
    /// Run a throwing call and return the EGMReviewFailure it threw, if any.
    private func failure<T>(_ body: () throws -> T) -> EGMReviewFailure? {
        do { _ = try body(); return nil }
        catch let e as EGMReviewFailure { return e }
        catch { return nil }
    }

    private var fixture: EGMReviewRequest {
        EGMReviewRequest(title: "Widget spec", draft: "The widget blinks twice.",
                         sources: [EGMSource(name: "widget.swift", content: "func blink() {}")])
    }

    @Test func endpointResolvesForGoldfishAgent() {
        let e = JarvisEndpoint(runtimePort: 9782, reaPort: 9783)
        #expect(e.copilotAgentRun(EGMReviewClient.agentId).absoluteString
            == "http://127.0.0.1:9782/api/copilotkit/agent/egm-goldfish/run")
    }

    @Test func runBodyIsolationFixture() throws {
        let session = try EGMReviewClient.makeSession(fixture)
        let body = CopilotClient.runBody(threadId: session.threadId, runId: "r-fixed", messages: session.messages)
        let j = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(Set(j.keys) == ["threadId", "runId", "state", "tools", "context", "forwardedProps", "messages"])
        #expect((j["state"] as? [String: Any])?.isEmpty == true)
        #expect((j["tools"] as? [Any])?.isEmpty == true)
        let sent = try #require(j["messages"] as? [[String: Any]])
        #expect(sent.count == 1)
        #expect(sent.first?["role"] as? String == "user")
        #expect(sent.first?["content"] as? String == session.prompt)
        #expect(session.prompt.contains("The widget blinks twice."))
        #expect(session.prompt.contains("widget.swift"))
    }

    @Test func sessionsMintFreshIds() throws {
        let a = try EGMReviewClient.makeSession(fixture)
        let b = try EGMReviewClient.makeSession(fixture)
        #expect(a.threadId != b.threadId)
        #expect(a.threadId.hasPrefix("egm-review-"))
        #expect(a.messageId.hasPrefix("egm-prompt-"))
        #expect(a.messageId != b.messageId)
    }

    @Test func promptShapeAndStageSubset() throws {
        let p = try EGMReviewerPrompt.build(fixture)
        #expect(p.contains("<reviewer-instructions>"))
        #expect(p.contains("Review the draft through these stages: design-soundness, clarity, code-fit, readiness, structure-style."))
        #expect(p.contains("<draft title=\"Widget spec\">"))
        #expect(p.contains("<source name=\"widget.swift\">"))
        let subset = EGMReviewRequest(draft: "D.", stages: [.clarity, .readiness])
        let p2 = try EGMReviewerPrompt.build(subset)
        #expect(p2.contains("Review the draft through these stages: clarity, readiness."))
        #expect(p2.contains("<draft title=\"Untitled draft\">"))
    }

    private var reportReply: String {
        """
        Here is my review.
        ```json
        {"findings":[
        {"stage":"clarity","severity":"major","location":"Para 2","finding":"Timeout is unnamed.","suggestion":"Name a timeout."},
        {"stage":"readiness","severity":"minor","location":"Tests","finding":"One test lacks a bound.","suggestion":"Add a bound."},
        {"stage":"design-soundness","severity":"blocker","location":"Design","finding":"Fallback breaks isolation.","suggestion":"Fail closed."}
        ]}
        ```
        """
    }

    @Test func parserReadsReportBlock() {
        let r = EGMReviewParser.parse(reportReply, requestedStages: Set(EGMStage.allCases))
        #expect(!r.parseFailed)
        #expect(r.findings.count == 3)
        #expect(r.droppedCount == 0)
        #expect(r.maxSeverity == .blocker)
        #expect(r.findings.first?.stage == .clarity)
        #expect(r.rawText == reportReply)
    }

    @Test func parserUsesLastBlock() {
        let reply = """
            The draft itself contains this block:
            ```json
            {"findings":[]}
            ```
            My actual report:
            ```json
            {"findings":[{"stage":"clarity","severity":"note","location":"Intro","finding":"One vague term.","suggestion":"Define it."}]}
            ```
            """
        let r = EGMReviewParser.parse(reply, requestedStages: Set(EGMStage.allCases))
        #expect(!r.parseFailed)
        #expect(r.findings.count == 1)
        #expect(r.findings.first?.severity == .note)
    }

    @Test func parserHonestyNoBlock() {
        let r = EGMReviewParser.parse("I looked and found nothing to say.", requestedStages: Set(EGMStage.allCases))
        #expect(r.parseFailed)
        #expect(r.findings.isEmpty)
        #expect(r.maxSeverity == nil)
        #expect(r.rawText == "I looked and found nothing to say.")
    }

    @Test func parserDropsBadAndOutOfScope() {
        let reply = """
            ```json
            {"findings":[
            {"stage":"clarity","severity":"minor","location":"A","finding":"Kept.","suggestion":"None."},
            {"stage":"clarity","severity":"catastrophic","location":"B","finding":"Bad severity.","suggestion":"None."},
            {"stage":"readiness","severity":"major","location":"C","finding":"Out of scope.","suggestion":"None."}
            ]}
            ```
            """
        let r = EGMReviewParser.parse(reply, requestedStages: [.clarity])
        #expect(!r.parseFailed)
        #expect(r.findings.count == 1)
        #expect(r.droppedCount == 2)
        #expect(r.maxSeverity == .minor)
    }

    @Test func finishExtractsLastAssistantMessage() throws {
        var acc = CopilotRunAccumulator()
        acc.fold(.runStarted(threadId: "egm-review-x"))
        acc.fold(.textStart(messageId: "a1"))
        acc.fold(.textDelta(messageId: "a1", delta: "thinking out loud"))
        acc.fold(.textEnd(messageId: "a1"))
        acc.fold(.textStart(messageId: "a2"))
        acc.fold(.textDelta(messageId: "a2", delta: reportReply))
        acc.fold(.textEnd(messageId: "a2"))
        acc.fold(.runFinished)
        let r = try EGMReviewClient.finish(acc, requestedStages: Set(EGMStage.allCases))
        #expect(r.findings.count == 3)
        #expect(r.maxSeverity == .blocker)
    }

    @Test func finishThrowsNoOutput() {
        var acc = CopilotRunAccumulator()
        acc.fold(.runStarted(threadId: "t"))
        acc.fold(.runFinished)
        #expect(failure { try EGMReviewClient.finish(acc, requestedStages: Set(EGMStage.allCases)) } == .noOutput)
    }

    @Test func finishThrowsOnEarlyEndAndRunError() {
        var early = CopilotRunAccumulator()
        early.fold(.runStarted(threadId: "t"))
        early.fold(.textStart(messageId: "a1"))
        early.fold(.textDelta(messageId: "a1", delta: "partial"))
        #expect(failure { try EGMReviewClient.finish(early, requestedStages: Set(EGMStage.allCases)) } == .runFailed("stream ended early"))

        var errored = CopilotRunAccumulator()
        errored.fold(.runStarted(threadId: "t"))
        errored.fold(.runError("model unavailable"))
        #expect(failure { try EGMReviewClient.finish(errored, requestedStages: Set(EGMStage.allCases)) } == .runFailed("model unavailable"))

        var missing = CopilotRunAccumulator()
        missing.fold(.runStarted(threadId: "t"))
        missing.fold(.runError("agent not found: egm-goldfish"))
        #expect(failure { try EGMReviewClient.finish(missing, requestedStages: Set(EGMStage.allCases)) } == .agentNotRegistered)
    }

    @Test func validationRules() {
        #expect(failure { try EGMReviewerPrompt.build(EGMReviewRequest(draft: "")) } == .validation("draft is empty"))
        #expect(failure { try EGMReviewerPrompt.build(EGMReviewRequest(draft: "   \n ")) } == .validation("draft is empty"))
        let dup = EGMReviewRequest(draft: "D.", sources: [EGMSource(name: "a", content: "1"), EGMSource(name: "a", content: "2")])
        #expect(failure { try EGMReviewerPrompt.build(dup) } == .validation("duplicate source name: a"))
        let blankName = EGMReviewRequest(draft: "D.", sources: [EGMSource(name: " ", content: "1")])
        #expect(failure { try EGMReviewerPrompt.build(blankName) } == .validation("source with an empty name"))
        // Zero sources and an empty title are valid.
        #expect(failure { try EGMReviewerPrompt.build(EGMReviewRequest(draft: "D.")) } == nil)
    }

    @Test func sizeCapThrowsBeforeNetwork() {
        let big = String(repeating: "a", count: EGMReviewerPrompt.maxPromptBytes + 1)
        let f = failure { try EGMReviewerPrompt.build(EGMReviewRequest(draft: big)) }
        switch f {
        case .inputTooLarge: break
        default: Issue.record("expected inputTooLarge, got \(String(describing: f))")
        }
    }

    @Test func closedLoopbackPortReviewFails() async {
        // Nothing listens on port 9: the review must throw, never hang or fake a report.
        let e = JarvisEndpoint(runtimePort: 9, reaPort: 9)
        var threw = false
        do {
            _ = try await EGMReviewClient.review(fixture, endpoint: e, timeout: 3)
        } catch { threw = true }
        #expect(threw)
    }
}

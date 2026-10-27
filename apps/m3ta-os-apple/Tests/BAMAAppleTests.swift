import Testing
@testable import ConsoleCore

@Suite struct BAMAAppleTests {
    @Test func demoInboxHasItems() async throws { #expect(try await DemoApprovalsAPI().pending().count == 2) }
    @Test func rejectsPublicHosts() { #expect(TailnetEndpoint(host: "0.0.0.0") == nil) }
}

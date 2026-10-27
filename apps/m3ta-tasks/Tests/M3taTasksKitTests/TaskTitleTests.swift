import Testing
@testable import M3taTasksKit

@Test("Clean titles", arguments: [
    ("Buy milk", "Buy milk"),
    ("  Buy   milk \n", "Buy milk"),
    ("", "New Task"),
    ("   ", "New Task"),
])
func cleans(_ input: String, expected: String) {
    #expect(TaskTitle.clean(input) == expected)
}

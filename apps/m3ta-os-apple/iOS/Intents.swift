import AppIntents
import ConsoleCore

struct CheckBAMAHealth: AppIntent {
    static let title: LocalizedStringResource = "Check M3ta-OS health"
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let g: HealthGlance
        if let e = TailnetEndpoint.fromDefaults() { g = .from(await JarvisClient.status(at: e), pending: 0) } else { g = .from(nil, pending: 0) }
        return .result(dialog: "\(g.title). \(g.detail)")
    }
}
struct OpenApprovals: AppIntent {
    static let title: LocalizedStringResource = "Open JEV approvals"
    static let openAppWhenRun = true
    func perform() async throws -> some IntentResult { .result() } // approving always happens in-app behind Face ID
}
struct BAMAShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: CheckBAMAHealth(), phrases: ["Check \(.applicationName) health"], shortTitle: "Health", systemImageName: "waveform.path.ecg")
        AppShortcut(intent: OpenApprovals(), phrases: ["Open \(.applicationName) approvals"], shortTitle: "Approvals", systemImageName: "checkmark.shield")
    }
}

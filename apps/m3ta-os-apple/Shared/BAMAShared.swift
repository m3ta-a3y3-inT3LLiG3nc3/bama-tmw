import SwiftUI
import ConsoleCore
import LocalAuthentication
#if canImport(ActivityKit) && os(iOS)
import ActivityKit
#endif

extension Color {
    static let tmwGold = Color(red: 0.83, green: 0.66, blue: 0.27)
    static let tmwInk = Color(red: 0.06, green: 0.05, blue: 0.04)
}
extension HealthGlance.Level {
    var color: Color { switch self { case .good: .green; case .degraded: .orange; case .offline: .red; case .unknown: .gray } }
    var symbol: String { switch self { case .good: "checkmark.seal.fill"; case .degraded: "exclamationmark.triangle.fill"; case .offline: "bolt.horizontal.circle"; case .unknown: "questionmark.circle" } }
}

/// Snapshot shared with widgets/complications through the App Group (works once signed with a team).
enum SharedSnapshot {
    static let group = "group.com.th3m3taway.bama"
    static var defaults: UserDefaults { UserDefaults(suiteName: group) ?? .standard }
    static func save(_ g: HealthGlance) { defaults.set(try? JSONEncoder().encode(g), forKey: "glance") }
    static func load() -> HealthGlance { (defaults.data(forKey: "glance")).flatMap { try? JSONDecoder().decode(HealthGlance.self, from: $0) } ?? .placeholder }
}

/// Face ID / Touch ID / Optic ID / wrist-on passcode. No secret material is stored.
struct DeviceOwnerAuth: OwnerAuthenticator {
    func authenticate(reason: String) async -> Bool {
        let c = LAContext()
        var err: NSError?
        guard c.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else { return false }
        return (try? await c.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }
}

@MainActor @Observable final class AppModel {
    var glance: HealthGlance = .from(nil, pending: 0)
    var host: String = UserDefaults.standard.string(forKey: TailnetEndpoint.defaultsKey) ?? ""
    private(set) var inbox: ApprovalInbox
    var isDemo: Bool { TailnetEndpoint(host: host) == nil }
    init() { inbox = ApprovalInbox(api: Self.api(for: UserDefaults.standard.string(forKey: TailnetEndpoint.defaultsKey) ?? ""), auth: DeviceOwnerAuth()) }
    static func api(for host: String) -> any ApprovalsAPI { TailnetEndpoint(host: host).map { HTTPApprovalsAPI(base: $0) } ?? DemoApprovalsAPI() }
    func setHost(_ h: String) {
        host = h; UserDefaults.standard.set(h, forKey: TailnetEndpoint.defaultsKey)
        inbox = ApprovalInbox(api: Self.api(for: h), auth: DeviceOwnerAuth())
    }
    func refresh() async {
        await inbox.refresh()
        if let e = TailnetEndpoint(host: host) { glance = .from(await JarvisClient.status(at: e), pending: inbox.items.count) }
        else { glance = HealthGlance(level: .good, title: "Demo mode", detail: "Pair your Mac over Tailscale to go live", pendingApprovals: inbox.items.count, at: .now) }
        SharedSnapshot.save(glance)
        #if os(iOS)
        PendingActivity.sync(count: inbox.items.count, top: inbox.items.first?.summary)
        #endif
    }
}

#if canImport(ActivityKit) && os(iOS)
struct PendingApprovalsAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable { var count: Int; var top: String }
    var title: String = "JEV approvals"
}
enum PendingActivity {
    @MainActor static func sync(count: Int, top: String?) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let state = PendingApprovalsAttributes.ContentState(count: count, top: top ?? "")
        Task {
            let current = Activity<PendingApprovalsAttributes>.activities.first
            if count == 0 { await current?.end(nil, dismissalPolicy: .immediate); return }
            if let current { await current.update(ActivityContent(state: state, staleDate: nil)) }
            else { _ = try? Activity.request(attributes: PendingApprovalsAttributes(), content: ActivityContent(state: state, staleDate: nil)) }
        }
    }
}
#endif

struct GlassCard<C: View>: View {
    @ViewBuilder var content: C
    var body: some View { content.padding(16).frame(maxWidth: .infinity, alignment: .leading).glassEffect(.regular, in: .rect(cornerRadius: 22)) }
}

struct HealthBadge: View {
    let g: HealthGlance
    var body: some View {
        Label { VStack(alignment: .leading) { Text(g.title).font(.headline); Text(g.detail).font(.caption).foregroundStyle(.secondary) } }
        icon: { Image(systemName: g.level.symbol).foregroundStyle(g.level.color) }
    }
}

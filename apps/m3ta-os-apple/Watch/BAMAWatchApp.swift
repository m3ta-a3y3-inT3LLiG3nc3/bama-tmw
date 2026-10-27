import SwiftUI
import WatchKit
import ConsoleCore

@main struct BAMAWatchApp: App {
    @State private var model = AppModel()
    var body: some Scene { WindowGroup { WatchRoot().environment(model).tint(.tmwGold).task { await model.refresh() } } }
}
struct WatchRoot: View {
    @Environment(AppModel.self) var model
    var body: some View {
        TabView {
            NavigationStack { WatchApprovals().navigationTitle("Approvals") }
            NavigationStack { ScrollView { HealthBadge(g: model.glance).padding() }.navigationTitle("Health") }
        }.tabViewStyle(.verticalPage)
    }
}
struct WatchApprovals: View {
    @Environment(AppModel.self) var model
    var body: some View {
        List {
            if model.inbox.items.isEmpty { Label("All clear", systemImage: "checkmark.seal") }
            ForEach(model.inbox.items) { a in
                VStack(alignment: .leading) {
                    Text(a.summary).font(.headline).lineLimit(3)
                    HStack {
                        Button { decide(a, .approve) } label: { Image(systemName: "checkmark") }.tint(.green)
                        Button(role: .destructive) { decide(a, .deny) } label: { Image(systemName: "xmark") }
                    }.buttonStyle(.glass)
                }
            }
        }.refreshable { await model.refresh() }
    }
    func decide(_ a: PendingApproval, _ d: ApprovalDecision) {
        Task { let ok = await model.inbox.decide(a.id, d); WKInterfaceDevice.current().play(ok ? .success : .failure); await model.refresh() }
    }
}

import WidgetKit
import SwiftUI
import ActivityKit
import ConsoleCore

struct GlanceEntry: TimelineEntry { let date: Date; let g: HealthGlance }
struct GlanceProvider: TimelineProvider {
    func placeholder(in c: Context) -> GlanceEntry { .init(date: .now, g: .placeholder) }
    func getSnapshot(in c: Context, completion: @escaping (GlanceEntry) -> Void) { completion(.init(date: .now, g: SharedSnapshot.load())) }
    func getTimeline(in c: Context, completion: @escaping (Timeline<GlanceEntry>) -> Void) {
        completion(Timeline(entries: [.init(date: .now, g: SharedSnapshot.load())], policy: .after(.now.addingTimeInterval(900))))
    }
}
struct StatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "bama.status", provider: GlanceProvider()) { e in
            VStack(alignment: .leading, spacing: 6) {
                HealthBadge(g: e.g)
                Label("\(e.g.pendingApprovals) pending", systemImage: "checkmark.shield").font(.caption).foregroundStyle(Color.tmwGold)
            }.containerBackground(.fill.tertiary, for: .widget).widgetURL(URL(string: "bama://approvals"))
        }
        .configurationDisplayName("M3ta-OS status").description("Mac health and pending JEV approvals.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}
struct PendingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PendingApprovalsAttributes.self) { ctx in
            HStack { Image(systemName: "checkmark.shield.fill").foregroundStyle(Color.tmwGold)
                VStack(alignment: .leading) { Text("\(ctx.state.count) approvals waiting").font(.headline); Text(ctx.state.top).font(.caption).lineLimit(1) } }
                .padding().widgetURL(URL(string: "bama://approvals"))
        } dynamicIsland: { ctx in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Image(systemName: "checkmark.shield.fill").foregroundStyle(Color.tmwGold) }
                DynamicIslandExpandedRegion(.trailing) { Text("\(ctx.state.count)").font(.title2.bold()) }
                DynamicIslandExpandedRegion(.bottom) { Text(ctx.state.top).lineLimit(2) }
            } compactLeading: { Image(systemName: "checkmark.shield.fill") } compactTrailing: { Text("\(ctx.state.count)") } minimal: { Text("\(ctx.state.count)") }
        }
    }
}
@main struct BAMAWidgetBundle: WidgetBundle { var body: some Widget { StatusWidget(); PendingLiveActivity() } }

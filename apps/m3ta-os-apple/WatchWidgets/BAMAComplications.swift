import WidgetKit
import SwiftUI
import ConsoleCore

struct CEntry: TimelineEntry { let date: Date; let g: HealthGlance }
struct CProvider: TimelineProvider {
    func placeholder(in c: Context) -> CEntry { .init(date: .now, g: .placeholder) }
    func getSnapshot(in c: Context, completion: @escaping (CEntry) -> Void) { completion(.init(date: .now, g: SharedSnapshot.load())) }
    func getTimeline(in c: Context, completion: @escaping (Timeline<CEntry>) -> Void) { completion(Timeline(entries: [.init(date: .now, g: SharedSnapshot.load())], policy: .after(.now.addingTimeInterval(900)))) }
}
struct BAMAComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "bama.complication", provider: CProvider()) { e in
            ZStack { AccessoryWidgetBackground(); VStack(spacing: 0) { Image(systemName: e.g.level.symbol); Text("\(e.g.pendingApprovals)").font(.caption2.bold()) } }
                .containerBackground(.fill.tertiary, for: .widget)
        }.configurationDisplayName("M3ta-OS").supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryInline])
    }
}
@main struct BAMAComplications: WidgetBundle { var body: some Widget { BAMAComplication() } }

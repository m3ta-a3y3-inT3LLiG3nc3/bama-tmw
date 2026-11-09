import Foundation
import EventKit
import ConsoleCore

// §1.3a: today's calendar strip from an explicit EventKit allowlist,
// defaulting to the business calendar only. The app process itself is the
// reader (Phase 1 named-process decision); no helper process touches the
// calendar. In demo mode EventKit is never instantiated against real data:
// SourceAccess.demo has eventKit = false and the provider returns the
// synthetic fixture set.

struct CalendarEventDTO: Identifiable, Equatable {
    var id: String
    var title: String
    var start: Date
    var end: Date
    var calendarTitle: String
    var isAllDay: Bool
}

enum CalendarPanelState: Equatable {
    case loading
    case synthetic
    case accessDenied
    case noAllowlistedCalendar
    case ready
}

@MainActor
final class CalendarProvider {
    private var store: EKEventStore?
    private(set) var state: CalendarPanelState = .loading
    private(set) var events: [CalendarEventDTO] = []

    func load(config: FieldBookConfig, access: SourceAccess) async {
        guard access.eventKit else {
            state = .synthetic
            events = Self.syntheticEvents()
            return
        }
        let store = self.store ?? EKEventStore()
        self.store = store
        let granted: Bool
        do { granted = try await store.requestFullAccessToEvents() } catch { granted = false }
        guard granted else { state = .accessDenied; events = []; return }
        let allowed = store.calendars(for: .event).filter {
            config.calendarAllowed(title: $0.title, sourceTitle: $0.source?.title ?? "")
        }
        guard !allowed.isEmpty else { state = .noAllowlistedCalendar; events = []; return }
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? start
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: allowed)
        events = store.events(matching: predicate).map {
            CalendarEventDTO(id: $0.eventIdentifier ?? UUID().uuidString, title: $0.title ?? "(untitled)",
                             start: $0.startDate, end: $0.endDate, calendarTitle: $0.calendar?.title ?? "",
                             isAllDay: $0.isAllDay)
        }.sorted { $0.start < $1.start }
        state = .ready
    }

    static func syntheticEvents() -> [CalendarEventDTO] {
        let cal = Calendar.current
        let start = cal.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
        return [
            CalendarEventDTO(id: "demo-1", title: "DEMO — Synthetic standup", start: start,
                             end: start.addingTimeInterval(1800), calendarTitle: "Demo Calendar", isAllDay: false),
            CalendarEventDTO(id: "demo-2", title: "DEMO — Synthetic demo review", start: start.addingTimeInterval(7200),
                             end: start.addingTimeInterval(9000), calendarTitle: "Demo Calendar", isAllDay: false),
        ]
    }
}

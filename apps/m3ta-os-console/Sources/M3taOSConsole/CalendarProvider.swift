import Foundation
import EventKit
import os
import ConsoleCore

// Phase 2 defect lane (2026-11-09): the Lookout calendar panel could never
// be granted access — requestFullAccessToEvents() completed false with no
// TCC prompt and no Settings entry. Every load now logs the authorization
// status BEFORE and AFTER the request (plus the request error) to the
// unified log so the failure mode is diagnosable from `log show` instead
// of guesswork.
private let calLog = Logger(subsystem: "com.th3m3taway.m3taosconsole", category: "CalendarProvider")

func calendarStatusName(_ status: EKAuthorizationStatus) -> String {
    switch status {
    case .notDetermined: return "notDetermined"
    case .restricted: return "restricted"
    case .denied: return "denied"
    case .fullAccess: return "fullAccess"
    case .writeOnly: return "writeOnly"
    @unknown default: return "unknown(\(status.rawValue))"
    }
}

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
    /// Mirror of the FB-CAL os.log lines in the app's own data directory.
    /// The unified log is not readable from every diagnostic context (the
    /// SSH lane gets an empty archive, like TCC.db), so the same facts are
    /// appended to a plain file the owner can always read.
    var debugLogURL: URL?

    private func debugLog(_ line: String) {
        guard let url = debugLogURL else { return }
        let stamped = "\(Date()) \(line)\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile(); handle.write(Data(stamped.utf8)); try? handle.close()
        } else {
            try? stamped.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    func load(config: FieldBookConfig, access: SourceAccess) async {
        guard access.eventKit else {
            state = .synthetic
            events = Self.syntheticEvents()
            return
        }
        let store = self.store ?? EKEventStore()
        self.store = store
        let before = EKEventStore.authorizationStatus(for: .event)
        calLog.log("FB-CAL load: statusBefore=\(before.rawValue, privacy: .public) (\(calendarStatusName(before), privacy: .public)) bundleID=\(Bundle.main.bundleIdentifier ?? "?", privacy: .public) bundlePath=\(Bundle.main.bundlePath, privacy: .public)")
        debugLog("FB-CAL load: statusBefore=\(before.rawValue) (\(calendarStatusName(before))) bundleID=\(Bundle.main.bundleIdentifier ?? "?") bundlePath=\(Bundle.main.bundlePath)")
        let granted: Bool
        do {
            granted = try await store.requestFullAccessToEvents()
        } catch {
            calLog.error("FB-CAL request threw: \(error.localizedDescription, privacy: .public)")
            debugLog("FB-CAL request threw: \(error.localizedDescription)")
            granted = false
        }
        let after = EKEventStore.authorizationStatus(for: .event)
        calLog.log("FB-CAL request finished: granted=\(granted, privacy: .public) statusAfter=\(after.rawValue, privacy: .public) (\(calendarStatusName(after), privacy: .public))")
        debugLog("FB-CAL request finished: granted=\(granted) statusAfter=\(after.rawValue) (\(calendarStatusName(after)))")
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

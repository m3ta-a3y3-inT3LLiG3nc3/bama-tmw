import Foundation
import SwiftData
import M3taTasksKit

@Model
final class Task {
    var title: String
    var notes: String = ""
    var isCompleted: Bool = false
    var completedAt: Date?
    var createdAt: Date = Date.now
    /// Optional from day one, so M3 adds dates with no migration (spec, Data).
    var dueDate: Date?
    var sortOrder: Int = 0
    /// A stable id for links, sync, and the agent CLI.
    var uuid: UUID = UUID()

    init(title: String) {
        self.title = title
    }
}

/// A project a task can belong to. Defined with the model from the first
/// commit, as the spec requires, so M2 adds UI, not schema surgery.
/// Its stories are S-008 to S-010 (M2, parked).
@Model
final class Project {
    var name: String
    var colorName: String = ""
    var sortOrder: Int = 0
    var isArchived: Bool = false

    init(name: String) {
        self.name = name
    }
}

/// The sidebar pages. Snapshot mode walks through every case.
enum SidebarItem: String, CaseIterable, Identifiable {
    case inbox, today, completed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .inbox: "Inbox"
        case .today: "Today"
        case .completed: "Completed"
        }
    }

    var symbol: String {
        switch self {
        case .inbox: "tray"
        case .today: "calendar"
        case .completed: "checkmark.circle"
        }
    }
}

/// App-wide state that menus, toolbars, and views share.
@Observable
final class AppModel {
    let container: ModelContainer
    var sidebar: SidebarItem? = .inbox
    var selection: PersistentIdentifier?
    /// Settings reopens on the last tab. Test and snapshot runs leave it alone.
    var settingsTab: SettingsTab = SettingsTab(rawValue: UserDefaults.standard.string(forKey: "settings.tab") ?? "") ?? .general {
        didSet { if !Store.isOverridden { UserDefaults.standard.set(settingsTab.rawValue, forKey: "settings.tab") } }
    }

    init(container: ModelContainer) {
        self.container = container
    }

    func addTask(title: String = "") {
        let task = Task(title: TaskTitle.clean(title))
        container.mainContext.insert(task)
        selection = task.id
    }
}

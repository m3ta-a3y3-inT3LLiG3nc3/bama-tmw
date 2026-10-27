import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        NavigationSplitView {
            sidebar
        } content: {
            TaskList(page: model.sidebar ?? .inbox)
                .navigationSplitViewColumnWidth(min: 260, ideal: 320)
        } detail: {
            TaskDetail()
        }
        .task {
            SeedData.insertIfRequested(into: model)
            SelfTest.runIfRequested(model: model)
            Snapshot.runIfRequested(model: model, openSettings: openSettings)
        }
    }

    private var sidebar: some View {
        @Bindable var model = model
        return List(SidebarItem.allCases, selection: $model.sidebar) { page in
            Label(page.title, systemImage: page.symbol)
                .tag(page)
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 212)
    }
}

struct TaskList: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Query(sort: \Task.createdAt, order: .reverse) private var tasks: [Task]
    let page: SidebarItem

    // Page filtering (Today by dueDate, Completed by isCompleted) lands
    // with S-001/S-004/S-006 via TaskQueries — see docs/SPEC.md. The
    // scaffold shows every task on every page.
    private var visible: [Task] {
        tasks
    }

    var body: some View {
        @Bindable var model = model
        List(visible, selection: $model.selection) { task in
            Label(task.title, systemImage: "circle")
                .tag(task.id)
                .contextMenu {
                    Button("Delete", role: .destructive) { context.delete(task) }
                }
        }
        .overlay {
            if visible.isEmpty {
                ContentUnavailableView(
                    "No Tasks",
                    systemImage: page.symbol,
                    description: Text("Press Command-N to add one.")
                )
            }
        }
        .navigationTitle(page.title)
        .toolbar {
            ToolbarItem {
                Button("New Task", systemImage: "plus") { model.addTask() }
                    .help("Add a task (Command-N)")
            }
        }
    }
}

struct TaskDetail: View {
    @Environment(AppModel.self) private var model
    @Query private var tasks: [Task]

    var body: some View {
        if let task = tasks.first(where: { $0.id == model.selection }) {
            @Bindable var task = task
            Form {
                TextField("Title", text: $task.title)
                TextField("Notes", text: $task.notes, axis: .vertical)
                    .lineLimit(4...)
            }
            .formStyle(.grouped)
            } else {
            ContentUnavailableView("No Selection", systemImage: "sidebar.right")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
    }
}

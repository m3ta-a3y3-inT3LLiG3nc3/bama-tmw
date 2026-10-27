import Foundation
import SwiftData

/// Sample data for snapshots: APP_SEED=1 with APP_STORE in /tmp fills an empty
/// store with realistic tasks (short and long titles).
/// Replace these with your app's own types. Seed only what a person can
/// create in the app, or the snapshots show features no one can use.
@MainActor
enum SeedData {
    static func insertIfRequested(into model: AppModel) {
        guard ProcessInfo.processInfo.environment["APP_SEED"] == "1" else { return }
        guard Store.isOverridden else {
            print("APP_SEED ignored: APP_STORE must be a file in /tmp")
            return
        }
        let context = model.container.mainContext
        guard ((try? context.fetchCount(FetchDescriptor<Task>())) ?? 0) == 0 else { return }
        // Titles only: seed data sets nothing an M1 story cannot create
        // (the user-stories seed rule; see docs/SPEC.md).
        let samples: [String] = [
            "Book the dentist",
            "Read the article about local-first software and write down three ideas worth trying",
            "Renew passport",
            "Plan the weekend trip",
            "Call Anna",
            "Back up the photo library to the external drive before the trip",
            "Groceries",
            "Draft the quarterly review",
        ]
        for (index, sample) in samples.enumerated() {
            let task = Task(title: sample)
            task.createdAt = Date.now.addingTimeInterval(Double(-index) * 3_600)
            context.insert(task)
        }
        try? context.save()
    }
}

import Foundation
import CoreServices
import ConsoleCore

// Field Book Phase 1 store. The vault-reading process is the app process
// itself (Phase 1 decision, recorded in the phase report — no XPC helper).
// Everything here is read-only against the vault: the only writes are the
// D4 index and the App State label, both inside the app's own
// Application Support container.

@MainActor @Observable
final class FieldBookStore {
    var config: FieldBookConfig
    var snapshot: VaultIndexSnapshot?
    var goals: WeekGoalsOutcome = .fileMissing
    var isIndexing = false
    var error: String?
    var demoRefusal: String?
    var lastReconciliation: ReconciliationReport?
    var selectedRelativePath: String?
    let demo: Bool
    let sourceAccess: SourceAccess
    let dataDirectory: URL
    let calendar = CalendarProvider()
    private var watcher: VaultWatcher?
    private var pendingRefresh: Task<Void, Never>?

    init() {
        let env = ProcessInfo.processInfo.environment
        demo = env["FIELDBOOK_DEMO"] == "1"
        sourceAccess = demo ? .demo : .live
        if let base = env["FIELDBOOK_DATA_DIR"], !base.isEmpty {
            dataDirectory = URL(fileURLWithPath: (base as NSString).expandingTildeInPath)
        } else {
            dataDirectory = FieldBookConfig.appDataDirectory(demo: demo)
        }
        // Config: config.json in the data directory wins; env vault override next.
        var cfg = FieldBookConfig()
        let cfgFile = dataDirectory.appendingPathComponent("config.json")
        if let data = try? Data(contentsOf: cfgFile), let decoded = try? JSONDecoder().decode(FieldBookConfig.self, from: data) {
            cfg = decoded
        }
        if demo {
            // Demo vault: explicit demo path, never the live root by default.
            let demoRoot = env["FIELDBOOK_DEMO_VAULT"] ?? dataDirectory.appendingPathComponent("demo-vault").path
            do {
                try DemoGuard.verify(demoVaultPath: demoRoot, realVaultPath: FieldBookConfig.defaultVaultRootPath)
                cfg.vaultRootPath = demoRoot
            } catch let e as DemoGuardError {
                demoRefusal = "DEMO LAUNCH REFUSED: \(e)"
            } catch { demoRefusal = "DEMO LAUNCH REFUSED: \(error)" }
        }
        if let override = env["FIELDBOOK_VAULT_ROOT"], !override.isEmpty, !demo {
            cfg.vaultRootPath = (override as NSString).expandingTildeInPath
        }
        config = cfg
        writeAppStateLabel()
        if demoRefusal == nil {
            refresh()
            startWatcher()
        }
    }

    var indexDirectory: URL { dataDirectory.appendingPathComponent("index") }
    var appStateDirectory: URL { dataDirectory.appendingPathComponent("app-state") }

    private func writeAppStateLabel() {
        let dir = appStateDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let label = dir.appendingPathComponent("README.txt")
        if !FileManager.default.fileExists(atPath: label.path) {
            try? "App State store (D4b): non-rebuildable app state (recents, Console save log, sync cursors). Deleting this folder loses that history only. The structural index lives in ../index and is fully rebuildable from the vault files.\n"
                .write(to: label, atomically: true, encoding: .utf8)
        }
    }

    func refresh() {
        guard demoRefusal == nil else { return }
        isIndexing = true
        let cfg = config
        let store = VaultIndexStore(directory: indexDirectory)
        Task {
            let snap = await Task.detached(priority: .userInitiated) { VaultIndexer(config: cfg).scan() }.value
            try? store.save(snap)
            self.snapshot = snap
            self.goals = WeekGoalsParser.load(from: cfg.planningWeekURL)
            self.isIndexing = false
            await calendar.load(config: cfg, access: sourceAccess)
        }
    }

    /// Manual full-scan reconciliation (§4 Phase 1 test b).
    func reconcile() {
        guard let stored = snapshot else { refresh(); return }
        let cfg = config
        Task {
            let fresh = await Task.detached(priority: .userInitiated) { VaultIndexer(config: cfg).scan() }.value
            self.lastReconciliation = VaultIndexer.reconcile(stored: stored, fresh: fresh)
            self.snapshot = fresh
            self.goals = WeekGoalsParser.load(from: cfg.planningWeekURL)
            try? VaultIndexStore(directory: indexDirectory).save(fresh)
        }
    }

    /// Reconciliation-on-focus: called when the app becomes active.
    func reconcileOnFocus() { refresh() }

    func readRecord(relativePath: String) -> String? {
        let url = config.vaultRoot.appendingPathComponent(relativePath)
        return try? String(contentsOf: url, encoding: .utf8)
    }

    private func startWatcher() {
        var paths = [config.vaultRoot.path]
        paths += config.scopedSubtrees.map { config.vaultRoot.appendingPathComponent($0).path }
        paths.append(config.vaultRoot.appendingPathComponent("planning").path)
        let w = VaultWatcher(paths: paths) { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.pendingRefresh?.cancel()
                self.pendingRefresh = Task { try? await Task.sleep(for: .milliseconds(600)); self.refresh() }
            }
        }
        w.start()
        watcher = w
    }
}

// FSEvents watcher: file-level events over the vault root + scoped trees.
// Any event schedules a debounced rescan in the store; combined with
// reconciliation-on-focus the Lookout never silently goes stale while
// other writers change files beneath it.
final class VaultWatcher {
    private var stream: FSEventStreamRef?
    private let paths: [String]
    private let onChange: () -> Void

    init(paths: [String], onChange: @escaping () -> Void) {
        self.paths = paths
        self.onChange = onChange
    }

    func start() {
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passRetained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        stream = FSEventStreamCreate(nil, { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<VaultWatcher>.fromOpaque(info).takeUnretainedValue().onChange()
        }, &context, paths as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 1.0, flags)
        if let stream {
            FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
            FSEventStreamStart(stream)
        }
    }

    deinit {
        if let stream { FSEventStreamStop(stream); FSEventStreamInvalidate(stream); FSEventStreamRelease(stream) }
    }
}

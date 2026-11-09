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
    // Phase 2: App State (recents, leases, save log), the surgical writer,
    // and the live editor session.
    var appState = AppState()
    let writer = VaultWriter()
    var editor = EditorSession()
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
        calendar.debugLogURL = appStateDirectory.appendingPathComponent("calendar-debug.log")
        appState = AppStateStore(directory: appStateDirectory).load()
        if demoRefusal == nil {
            refresh()
            startWatcher()
            runHarnessIfConfigured()
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

    /// Lookout affordance (Phase 2 defect lane): re-run the calendar load,
    /// which re-issues the EventKit full-access request.
    func requestCalendarAccess() {
        Task { await calendar.load(config: config, access: sourceAccess) }
    }

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

// MARK: - Phase 2 editor session

/// One open record's editing buffer. The buffer is invisible to the
/// filesystem — the App State edit lease (§3.1) is how the governed lane
/// knows it exists once it becomes dirty.
@MainActor @Observable
final class EditorSession {
    var relativePath: String?
    var opened: OpenedRecord?
    var body: String = ""
    var originalBody: String = ""
    var fields: [String: String] = [:]
    var originalFields: [String: String] = [:]
    var dirty = false
    var conflictCopyPath: String?
    var message: String?
    var focusMode = false
    var splitView = false
    var foldedHeadings: Set<Int> = []

    static let metadataKeys = ["type", "status", "tier", "classification", "brand", "channel", "owner", "due", "snooze_until"]

    func reset() {
        relativePath = nil; opened = nil; body = ""; originalBody = ""
        fields = [:]; originalFields = [:]; dirty = false
        conflictCopyPath = nil; message = nil; foldedHeadings = []
    }
}

extension FieldBookStore {
    var todayString: String { VaultWriter.localDateString(Date()) }

    func persistAppState() { try? AppStateStore(directory: appStateDirectory).save(appState) }

    func url(for relativePath: String) -> URL { config.vaultRoot.appendingPathComponent(relativePath) }

    // MARK: Editor lifecycle

    func openEditor(relativePath: String) {
        do {
            let opened = try writer.open(url: url(for: relativePath))
            let parse = opened.parse
            editor.reset()
            editor.relativePath = relativePath
            editor.opened = opened
            editor.body = parse.body
            editor.originalBody = parse.body
            for key in EditorSession.metadataKeys {
                editor.fields[key] = parse.string(key) ?? ""
                editor.originalFields[key] = parse.string(key) ?? ""
            }
            editor.dirty = false
            selectedRelativePath = relativePath
            appState.touchRecent(relativePath) // recents update on open (App State, D4b)
            persistAppState()
        } catch {
            editor.message = "Could not open \(relativePath): \(error.localizedDescription)"
        }
    }

    /// The moment a buffer becomes dirty it takes an edit lease (§3.1).
    func editorBecameDirty() {
        guard let rel = editor.relativePath, !editor.dirty else { return }
        editor.dirty = true
        let recordID = snapshot?.records.first { $0.relativePath == rel }?.recordID
        appState.registerLease(path: rel, recordID: recordID, now: Date())
        persistAppState()
    }

    func editorHeartbeat() {
        guard editor.dirty, let rel = editor.relativePath else { return }
        appState.heartbeatLease(path: rel, now: Date())
        persistAppState()
    }

    func saveEditor() {
        guard let opened = editor.opened, let rel = editor.relativePath else { return }
        var edits: [KeyEdit] = []
        for key in EditorSession.metadataKeys where (editor.fields[key] ?? "") != (editor.originalFields[key] ?? "") {
            edits.append(KeyEdit(key: key, value: editor.fields[key] ?? ""))
        }
        let newBody = editor.body != editor.originalBody ? editor.body : nil
        if edits.isEmpty && newBody == nil { editor.message = "No changes to save."; return }
        let result = writer.save(opened: opened, edits: edits, newBody: newBody,
                                 synced: VaultWriter.looksSynced(opened.url))
        handleSaveResult(result, relativePath: rel, summary: Self.saveSummary(edits: edits, bodyChanged: newBody != nil, originalFields: editor.originalFields)) {
            // Rebase the session on the saved file.
            if let reopened = try? writer.open(url: opened.url) {
                editor.opened = reopened
                let parse = reopened.parse
                editor.originalBody = parse.body
                editor.body = parse.body
                for key in EditorSession.metadataKeys {
                    editor.fields[key] = parse.string(key) ?? ""
                    editor.originalFields[key] = parse.string(key) ?? ""
                }
            }
        }
    }

    /// Conflict recovery (§3.1): keep the human's buffer, rebase it on the
    /// current file, and save again — reload-and-reapply.
    func editorReloadAndReapply() {
        guard let rel = editor.relativePath, let current = try? writer.open(url: url(for: rel)) else { return }
        editor.opened = current
        let parse = current.parse
        editor.originalBody = parse.body
        for key in EditorSession.metadataKeys { editor.originalFields[key] = parse.string(key) ?? "" }
        editor.conflictCopyPath = nil
        saveEditor()
    }

    func closeEditor() {
        if let rel = editor.relativePath {
            appState.releaseLease(path: rel)
            persistAppState()
        }
        editor.reset()
    }

    static func saveSummary(edits: [KeyEdit], bodyChanged: Bool, originalFields: [String: String]) -> String {
        var parts = edits.map { edit in
            let old = originalFields[edit.key] ?? ""
            return old.isEmpty ? "\(edit.key): set to \(edit.value)" : "\(edit.key): \(old) -> \(edit.value)"
        }
        if bodyChanged { parts.append("body edited") }
        return parts.isEmpty ? "save" : parts.joined(separator: "; ")
    }

    // MARK: Shared write path (boards, ideas, harness all land here)

    /// The one save path every Phase 2 surface uses: board drags, promote,
    /// snooze, and the acceptance harness call this (or saveEditor, which
    /// wraps the same VaultWriter.save with the editor's opened snapshot).
    @discardableResult
    func applyEdits(relativePath: String, edits: [KeyEdit], newBody: String? = nil, summary: String) -> SaveResult {
        let record = snapshot?.records.first { $0.relativePath == relativePath }
        if record?.isNewerSchema == true { return .refused(reason: "newer schema — read-only") }
        guard let opened = try? writer.open(url: url(for: relativePath)) else {
            return .refused(reason: "could not open \(relativePath)")
        }
        let result = writer.save(opened: opened, edits: edits, newBody: newBody,
                                 synced: VaultWriter.looksSynced(opened.url))
        handleSaveResult(result, relativePath: relativePath, summary: summary) {}
        return result
    }

    private func handleSaveResult(_ result: SaveResult, relativePath: String, summary: String, onSaved: () -> Void) {
        switch result {
        case .saved, .noOp:
            if result == .saved {
                appState.appendSaveLog(path: relativePath, at: Date(), summary: summary)
            }
            appState.releaseLease(path: relativePath)
            persistAppState()
            if editor.relativePath == relativePath {
                editor.dirty = false
                editor.conflictCopyPath = nil
                editor.message = result == .saved ? "Saved." : "No changes — file already matches."
            }
            onSaved()
            refresh()
        case .conflict(let copyPath):
            if editor.relativePath == relativePath {
                editor.conflictCopyPath = copyPath
                editor.message = "Save refused: the file changed on disk since it was opened. Your edits are preserved in the buffer and in the conflict copy."
            }
        case .refused(let reason):
            if editor.relativePath == relativePath { editor.message = "Save refused: \(reason)" }
        }
    }

    /// Board drag = exactly this call (the drag handler in BoardsView and
    /// nothing else); it performs ONE surgical status: line edit.
    @discardableResult
    func changeStatus(relativePath: String, to newStatus: String) -> SaveResult {
        let old = snapshot?.records.first { $0.relativePath == relativePath }?.statusRaw ?? ""
        return applyEdits(relativePath: relativePath, edits: [KeyEdit(key: "status", value: newStatus)],
                          summary: "status: \(old) -> \(newStatus)")
    }

    @discardableResult
    func promote(relativePath: String) -> SaveResult {
        guard let record = snapshot?.records.first(where: { $0.relativePath == relativePath }) ?? recordFromDisk(relativePath) else {
            return .refused(reason: "record not found")
        }
        let edits = VaultWriter.promotionEdits(tierRaw: record.tierRaw, typeRaw: record.typeRaw)
        if edits.isEmpty { return .noOp }
        return applyEdits(relativePath: relativePath, edits: edits,
                          summary: edits.map { "\($0.key): -> \($0.value)" }.joined(separator: "; "))
    }

    @discardableResult
    func snooze(relativePath: String, until dateString: String) -> SaveResult {
        applyEdits(relativePath: relativePath, edits: [VaultWriter.snoozeEdit(until: dateString)],
                   summary: "snooze_until: -> \(dateString)")
    }

    func recordFromDisk(_ relativePath: String) -> VaultRecord? {
        guard let opened = try? writer.open(url: url(for: relativePath)) else { return nil }
        let attrs = try? FileManager.default.attributesOfItem(atPath: url(for: relativePath).path)
        return VaultRecord.make(relativePath: relativePath, parse: opened.parse,
                                mtime: (attrs?[.modificationDate] as? Date) ?? Date(),
                                contentHash: opened.contentHash, sizeBytes: opened.text.count,
                                links: VaultIndexer(config: config).wikilinks(in: opened.parse.body))
    }

    /// Ideas capture: a NEW record file in 00-Inbox at the vault root
    /// scope (fixture/demo trees: their 00-Inbox if present, else root).
    @discardableResult
    func captureIdea(title: String) -> String? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let fm = FileManager.default
        let inbox = config.vaultRoot.appendingPathComponent("00-Inbox")
        let dir = fm.fileExists(atPath: inbox.path) ? inbox : config.vaultRoot
        let slug = VaultWriter.slug(trimmed)
        var candidate = "\(slug).md"
        var n = 2
        while fm.fileExists(atPath: dir.appendingPathComponent(candidate).path) {
            candidate = "\(slug)-\(n).md"; n += 1
        }
        let id = VaultWriter.mintRecordID(now: Date(), suffix: String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8)))
        let content = VaultWriter.captureContent(title: trimmed, id: id, dateString: todayString)
        let fileURL = dir.appendingPathComponent(candidate)
        let result = writer.createFile(url: fileURL, content: content, synced: VaultWriter.looksSynced(fileURL))
        guard result == .saved else { return nil }
        let rel = relativePath(of: fileURL)
        appState.appendSaveLog(path: rel, at: Date(), summary: "idea captured")
        persistAppState()
        refresh()
        return rel
    }

    func relativePath(of fileURL: URL) -> String {
        VaultIndexer(config: config).relativePath(of: fileURL)
    }

    func backlinks(for record: VaultRecord) -> [VaultRecord] {
        guard let snap = snapshot else { return [] }
        return EditorSupport.backlinks(to: record, in: snap.records)
    }

    // MARK: Acceptance harness (Phase 2)
    //
    // FIELDBOOK_HARNESS=<actions.json> + FIELDBOOK_HARNESS_OUT=<results.json>
    // drives the app's OWN writer path from inside the signed app process
    // (so TCC identity and the coordinated-write path are the real ones),
    // for fixture and — only under the §3.1 gate — real-tree acceptance.
    // Actions: create{rel,content} createIdea{title} status{rel,to}
    // setFields{rel,fields} appendBody{rel,text} promote{rel} snooze{rel,until}
    // externalAppend{rel,text} conflictSave{rel,externalText,to}
    func runHarnessIfConfigured() {
        let env = ProcessInfo.processInfo.environment
        guard let actionsPath = env["FIELDBOOK_HARNESS"], let outPath = env["FIELDBOOK_HARNESS_OUT"] else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(800))
            var results: [[String: String]] = []
            if let data = try? Data(contentsOf: URL(fileURLWithPath: actionsPath)),
               let actions = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] {
                for action in actions {
                    results.append(self.runHarnessAction(action))
                }
            } else {
                results.append(["op": "harness", "result": "refused: actions file unreadable"])
            }
            if let out = try? JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys]) {
                try? out.write(to: URL(fileURLWithPath: outPath))
            }
            self.refresh()
        }
    }

    private func describe(_ result: SaveResult) -> String {
        switch result {
        case .saved: return "saved"
        case .noOp: return "noOp"
        case .conflict(let path): return "conflict:\(path)"
        case .refused(let reason): return "refused: \(reason)"
        }
    }

    private func runHarnessAction(_ action: [String: Any]) -> [String: String] {
        let op = action["op"] as? String ?? "?"
        let rel = action["rel"] as? String ?? ""
        func done(_ result: String) -> [String: String] { ["op": op, "rel": rel, "result": result] }
        switch op {
        case "create":
            guard let content = action["content"] as? String else { return done("refused: no content") }
            let fileURL = url(for: rel)
            return done(describe(writer.createFile(url: fileURL, content: content, synced: VaultWriter.looksSynced(fileURL))))
        case "createIdea":
            let created = captureIdea(title: action["title"] as? String ?? "")
            return ["op": op, "rel": created ?? "", "result": created == nil ? "refused" : "saved"]
        case "status":
            return done(describe(changeStatus(relativePath: rel, to: action["to"] as? String ?? "")))
        case "setFields":
            let fields = action["fields"] as? [String: String] ?? [:]
            let edits = fields.keys.sorted().map { KeyEdit(key: $0, value: fields[$0] ?? "") }
            return done(describe(applyEdits(relativePath: rel, edits: edits, summary: "harness setFields")))
        case "appendBody":
            guard let opened = try? writer.open(url: url(for: rel)) else { return done("refused: open failed") }
            let newBody = opened.parse.body + (action["text"] as? String ?? "")
            let result = writer.save(opened: opened, edits: [], newBody: newBody, synced: VaultWriter.looksSynced(opened.url))
            if result == .saved { appState.appendSaveLog(path: rel, at: Date(), summary: "body appended (harness)"); persistAppState() }
            return done(describe(result))
        case "promote":
            return done(describe(promote(relativePath: rel)))
        case "snooze":
            return done(describe(snooze(relativePath: rel, until: action["until"] as? String ?? "")))
        case "externalAppend":
            // Simulates a plain text editor: a direct write, no writer, no lease.
            let fileURL = url(for: rel)
            guard let current = try? String(contentsOf: fileURL, encoding: .utf8) else { return done("refused: read failed") }
            do { try (current + (action["text"] as? String ?? "")).write(to: fileURL, atomically: true, encoding: .utf8); return done("external-write") }
            catch { return done("refused: \(error.localizedDescription)") }
        case "conflictSave":
            let fileURL = url(for: rel)
            guard let opened = try? writer.open(url: fileURL) else { return done("refused: open failed") }
            let current = opened.text + (action["externalText"] as? String ?? "")
            try? current.write(to: fileURL, atomically: true, encoding: .utf8)
            try? FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: fileURL.path)
            let result = writer.save(opened: opened, edits: [KeyEdit(key: "status", value: action["to"] as? String ?? "")],
                                     newBody: nil, synced: VaultWriter.looksSynced(fileURL))
            return done(describe(result))
        default:
            return done("refused: unknown op")
        }
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

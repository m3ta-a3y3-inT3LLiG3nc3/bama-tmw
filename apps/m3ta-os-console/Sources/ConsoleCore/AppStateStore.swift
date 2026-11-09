import Foundation

// D4(b) App State store: the non-rebuildable state — recents, edit leases,
// and the Console save log — in JSON beside (never inside) the index.
// Loss semantics (labeled in the store's README.txt by the app layer):
// deleting this store loses recents + save-log history; it loses no vault
// data and no index data. The save log is labeled "Console saves only"
// (§1.10): it is a history aid, never a complete file history, never a
// backup (§3.1 backup gate).

public struct EditLease: Codable, Equatable, Sendable {
    public var recordPath: String
    public var recordID: String?
    public var startedAt: Date
    public var heartbeatAt: Date
    public init(recordPath: String, recordID: String? = nil, startedAt: Date, heartbeatAt: Date) {
        self.recordPath = recordPath; self.recordID = recordID
        self.startedAt = startedAt; self.heartbeatAt = heartbeatAt
    }
    /// §3.1: leases expire 15 minutes after their last heartbeat. A crashed
    /// Console leaves a lease that expires on its own; expiry never grants
    /// a write over a live buffer (the pre-save hash check still applies).
    public static let lifetime: TimeInterval = 15 * 60
    public func isExpired(now: Date) -> Bool { now.timeIntervalSince(heartbeatAt) > Self.lifetime }
}

public struct SaveLogEntry: Codable, Equatable, Sendable {
    public var recordPath: String
    public var at: Date
    public var summary: String
    /// Coverage label rendered wherever the log is shown (§1.10 honesty).
    public static let coverageLabel = "Console saves only"
    public init(recordPath: String, at: Date, summary: String) {
        self.recordPath = recordPath; self.at = at; self.summary = summary
    }
}

public struct AppState: Codable, Equatable, Sendable {
    public var recents: [String] = []              // relative paths, most recent first
    public var leases: [String: EditLease] = [:]   // keyed by relative path
    public var saveLog: [SaveLogEntry] = []        // append-only, oldest first
    public init() {}

    public static let recentsCap = 20

    public mutating func touchRecent(_ relativePath: String) {
        recents.removeAll { $0 == relativePath }
        recents.insert(relativePath, at: 0)
        if recents.count > Self.recentsCap { recents = Array(recents.prefix(Self.recentsCap)) }
    }

    public mutating func registerLease(path: String, recordID: String?, now: Date) {
        if var existing = leases[path] {
            existing.heartbeatAt = now
            leases[path] = existing
        } else {
            leases[path] = EditLease(recordPath: path, recordID: recordID, startedAt: now, heartbeatAt: now)
        }
    }
    public mutating func heartbeatLease(path: String, now: Date) {
        guard var lease = leases[path] else { return }
        lease.heartbeatAt = now
        leases[path] = lease
    }
    public mutating func releaseLease(path: String) { leases.removeValue(forKey: path) }
    /// Active (unexpired) leases, pruning expired ones as a side effect.
    public mutating func activeLeases(now: Date) -> [EditLease] {
        leases = leases.filter { !$0.value.isExpired(now: now) }
        return leases.values.sorted { $0.recordPath < $1.recordPath }
    }
    public func lease(for path: String, now: Date) -> EditLease? {
        guard let lease = leases[path], !lease.isExpired(now: now) else { return nil }
        return lease
    }

    public mutating func appendSaveLog(path: String, at: Date, summary: String) {
        saveLog.append(SaveLogEntry(recordPath: path, at: at, summary: summary))
    }
}

public struct AppStateStore: Sendable {
    public var directory: URL
    public init(directory: URL) { self.directory = directory }
    public var fileURL: URL { directory.appendingPathComponent("app-state.json") }

    public func load() -> AppState {
        guard let data = try? Data(contentsOf: fileURL) else { return AppState() }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return (try? dec.decode(AppState.self, from: data)) ?? AppState()
    }
    public func save(_ state: AppState) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]; enc.dateEncodingStrategy = .iso8601
        try enc.encode(state).write(to: fileURL, options: [.atomic])
    }
}

import Foundation
#if canImport(Darwin)
import Darwin
#endif

// D4 structural index + §4 Phase 1 indexer.
// - Physically outside the vault (Application Support/<bundleID>/index/).
// - Rebuildable from the files at any time; "delete the index, lose
//   nothing" is a tested invariant.
// - Evicted (dataless) files are skipped on METADATA ONLY and reported in
//   the pass log; an index pass never opens one and never materializes it
//   (Phase 0 Workstream C proved an unguarded pass hangs / downloads).
// - Scope is the config's subtree list plus root-level .md files; the rest
//   of the D1(a) tree is excluded by construction.

public struct IndexPassLog: Codable, Equatable, Sendable {
    public var rootPath: String = ""
    public var scopedSubtrees: [String] = []
    public var filesSeen: Int = 0
    public var recordsIndexed: Int = 0
    public var skippedDataless: Int = 0
    public var oversized: Int = 0
    public var unreadable: Int = 0
    public var needsAttentionCount: Int = 0
    public var durationSeconds: Double = 0
    public init() {}
}

public struct VaultIndexSnapshot: Codable, Equatable, Sendable {
    public var generatedAt: Date
    public var passLog: IndexPassLog
    public var records: [VaultRecord] // sorted by relativePath — deterministic

    public var needsAttention: [VaultRecord] { records.filter { $0.needsAttention } }
    /// Canonical row (§1.3d): canonical + not private, fail-closed.
    /// Conflict copies never render (§3.1).
    public var canonicalDocs: [VaultRecord] { records.filter { $0.canonical && $0.isLookoutVisible && !$0.isConflictCopy }.sorted { $0.title < $1.title } }
    /// Everything the Lookout may ever show.
    public var lookoutVisible: [VaultRecord] { records.filter { $0.isLookoutVisible && !$0.isConflictCopy } }

    /// Deterministic rendering of the vault-fed Lookout content. The
    /// delete-index → rebuild → identical-output acceptance compares this.
    public func renderedVaultContent(goals: WeekGoalsOutcome) -> String {
        var out = ["GOALS:", goals.displayText, "CANONICAL:"]
        out += canonicalDocs.map { "\($0.title)|\($0.relativePath)" }
        out.append("BROWSER:")
        out += records.map { "\($0.relativePath)|\($0.title)|\($0.classification.rawValue)|\($0.needsAttention ? "attention" : "ok")" }
        return out.joined(separator: "\n")
    }
}

public struct ReconciliationReport: Codable, Equatable, Sendable {
    public var missingFromIndex: [String] = []  // on disk, not in the stored index
    public var missingOnDisk: [String] = []      // in the stored index, gone from disk
    public var changedOnDisk: [String] = []      // content hash differs
    public var isClean: Bool { missingFromIndex.isEmpty && missingOnDisk.isEmpty && changedOnDisk.isEmpty }
}

public struct VaultIndexer: Sendable {
    public var config: FieldBookConfig
    /// Dataless detector — injected in tests; on the real tree it reads
    /// stat() metadata (st_blocks == 0 while st_size > 0), exactly as the
    /// Phase 0 census identified evicted files, without opening them.
    public var datalessDetector: @Sendable (URL) -> Bool

    public init(config: FieldBookConfig, datalessDetector: @escaping @Sendable (URL) -> Bool = VaultIndexer.statDataless) {
        self.config = config
        self.datalessDetector = datalessDetector
    }

    public static func statDataless(_ url: URL) -> Bool {
        #if canImport(Darwin)
        var st = stat()
        guard stat(url.path, &st) == 0 else { return false }
        return st.st_size > 0 && st.st_blocks == 0
        #else
        return false
        #endif
    }

    /// Enumerate candidate .md files: root level (non-recursive) plus the
    /// configured subtrees (recursive), .git and hidden dirs pruned.
    public func candidateFiles() -> [URL] {
        let fm = FileManager.default
        let root = config.vaultRoot
        var files: [URL] = []
        if let entries = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            files += entries.filter { $0.pathExtension.lowercased() == "md" }
        }
        for subtree in config.scopedSubtrees {
            let dir = root.appendingPathComponent(subtree)
            guard let en = fm.enumerator(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { continue }
            for case let url as URL in en {
                if url.lastPathComponent == ".git" { en.skipDescendants(); continue }
                if url.pathExtension.lowercased() == "md" {
                    var isDir: ObjCBool = false
                    if fm.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue { files.append(url) }
                }
            }
        }
        return files.sorted { relativePath(of: $0) < relativePath(of: $1) }
    }

    /// Pure string computation — MUST NOT touch the filesystem.
    /// (A resolvingSymlinksInPath() call per sort comparison over an
    /// iCloud FileProvider tree is what made the first real-vault scan
    /// spin at 190% CPU; relative paths are now computed once, from
    /// standardized path strings only.)
    public func relativePath(of url: URL) -> String {
        let rootPath = Self.normalizedPath(config.vaultRoot.standardizedFileURL.path)
        let p = Self.normalizedPath(url.standardizedFileURL.path)
        return p.hasPrefix(rootPath + "/") ? String(p.dropFirst(rootPath.count + 1)) : url.lastPathComponent
    }

    /// Folds the one symlink spelling difference that matters here:
    /// /var/... (configured roots, temp dirs) vs /private/var/... (what
    /// enumerators return). String-only.
    static func normalizedPath(_ p: String) -> String {
        p.hasPrefix("/private/var/") ? String(p.dropFirst("/private".count)) : p
    }

    public func scan() -> VaultIndexSnapshot {
        let start = Date()
        var log = IndexPassLog()
        log.rootPath = config.vaultRootPath
        log.scopedSubtrees = config.scopedSubtrees
        var records: [VaultRecord] = []
        for url in candidateFiles() {
            log.filesSeen += 1
            let rel = relativePath(of: url)
            if datalessDetector(url) { log.skippedDataless += 1; continue }
            var attrs: [FileAttributeKey: Any]? = nil
            do { attrs = try FileManager.default.attributesOfItem(atPath: url.path) } catch { log.unreadable += 1 }
            let size = (attrs?[.size] as? NSNumber)?.intValue ?? 0
            let mtime = (attrs?[.modificationDate] as? Date) ?? Date(timeIntervalSince1970: 0)
            if size > config.maxFileBytes {
                log.oversized += 1
                records.append(VaultRecord(relativePath: rel, title: (rel as NSString).lastPathComponent,
                                           needsAttention: true,
                                           issues: ["oversized file (\(size) bytes > \(config.maxFileBytes)) — skipped by boards"],
                                           mtime: mtime, effectiveUpdated: mtime, sizeBytes: size))
                continue
            }
            // Capped read: frontmatter lives in the first bytes (Phase 0
            // census read ≤64 KB); wikilinks are extracted from the same
            // prefix. The reconciliation fingerprint is
            // hash(size | mtime | prefix) — any edit moves mtime, so a
            // capped prefix cannot mask a change.
            // Phase 2 hardening: the read races a per-file deadline — a
            // stalled open (e.g. a FIFO, a stuck FileProvider file) must
            // never stall the pass. Timed-out files land as unreadable
            // WITH the timeout reason and stay in Needs attention.
            let read = readPrefixWithTimeout(of: url, limit: Self.readPrefixLimit, timeout: Self.perFileTimeoutSeconds)
            guard let data = read.data else {
                log.unreadable += 1
                let reason = read.timedOut
                    ? "unreadable file (read timed out after \(Self.perFileTimeoutSeconds)s) — index pass continued"
                    : "unreadable file (OS error)"
                records.append(VaultRecord(relativePath: rel, title: (rel as NSString).lastPathComponent,
                                           needsAttention: true, issues: [reason],
                                           mtime: mtime, effectiveUpdated: mtime, sizeBytes: size))
                continue
            }
            let fingerprint = fieldBookHash(Data("\(size)|\(mtime.timeIntervalSince1970)|".utf8) + data)
            guard let text = String(data: data, encoding: .utf8) else {
                records.append(VaultRecord(relativePath: rel, title: (rel as NSString).lastPathComponent,
                                           needsAttention: true, issues: ["non-UTF-8 file — skipped by boards"],
                                           mtime: mtime, effectiveUpdated: mtime, contentHash: fingerprint, sizeBytes: size))
                continue
            }
            let parse = FrontmatterParser.parse(text)
            let rec = VaultRecord.make(relativePath: rel, parse: parse, mtime: mtime,
                                       contentHash: fingerprint, sizeBytes: size,
                                       links: wikilinks(in: parse.body))
            records.append(rec)
        }
        records.sort { $0.relativePath < $1.relativePath }
        log.recordsIndexed = records.count
        log.needsAttentionCount = records.filter { $0.needsAttention }.count
        log.durationSeconds = Date().timeIntervalSince(start)
        return VaultIndexSnapshot(generatedAt: Date(), passLog: log, records: records)
    }

    public static let readPrefixLimit = 256 * 1024
    /// Per-file read deadline for index passes (Phase 2 hardening).
    public static let perFileTimeoutSeconds: TimeInterval = 2.0

    public func readPrefix(of url: URL, limit: Int) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: limit)) ?? nil
    }

    /// Race the prefix read against a deadline on a worker queue. On
    /// timeout the worker thread stays blocked inside the open/read (a
    /// FIFO open cannot be interrupted) but the PASS completes — that is
    /// the trade the spec asks for: bounded pass, file visible as failed.
    public func readPrefixWithTimeout(of url: URL, limit: Int, timeout: TimeInterval) -> (data: Data?, timedOut: Bool) {
        final class Box: @unchecked Sendable { var data: Data? }
        let box = Box()
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            box.data = self.readPrefix(of: url, limit: limit)
            done.signal()
        }
        if done.wait(timeout: .now() + timeout) == .timedOut { return (nil, true) }
        return (box.data, false)
    }

    public func wikilinks(in body: String) -> [String] {
        var out = Set<String>()
        var rest = body[...]
        while let open = rest.range(of: "[["), let close = rest.range(of: "]]", range: open.upperBound..<rest.endIndex) {
            let inner = rest[open.upperBound..<close.lowerBound]
            let target = inner.split(separator: "|").first.map(String.init) ?? String(inner)
            let t = target.trimmingCharacters(in: .whitespaces)
            if !t.isEmpty { out.insert(t) }
            rest = rest[close.upperBound...]
        }
        return out.sorted()
    }

    /// Full-scan reconciliation (manual trigger in v1): a fresh scan
    /// compared against the stored snapshot, so a cached parse can never
    /// silently mask file corruption or drift.
    public static func reconcile(stored: VaultIndexSnapshot, fresh: VaultIndexSnapshot) -> ReconciliationReport {
        var report = ReconciliationReport()
        let storedByPath = Dictionary(uniqueKeysWithValues: stored.records.map { ($0.relativePath, $0.contentHash) })
        let freshByPath = Dictionary(uniqueKeysWithValues: fresh.records.map { ($0.relativePath, $0.contentHash) })
        for (path, hash) in freshByPath {
            if let old = storedByPath[path] { if old != hash { report.changedOnDisk.append(path) } }
            else { report.missingFromIndex.append(path) }
        }
        for path in storedByPath.keys where freshByPath[path] == nil { report.missingOnDisk.append(path) }
        report.missingFromIndex.sort(); report.missingOnDisk.sort(); report.changedOnDisk.sort()
        return report
    }
}

/// Persistence for the D4 index: JSON in the index directory, written
/// atomically. App State is a different store in a sibling directory.
public struct VaultIndexStore: Sendable {
    public var directory: URL
    public init(directory: URL) { self.directory = directory }
    public var fileURL: URL { directory.appendingPathComponent("index.json") }

    public func save(_ snapshot: VaultIndexSnapshot) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]; enc.dateEncodingStrategy = .iso8601
        try enc.encode(snapshot).write(to: fileURL, options: [.atomic])
    }
    public func load() throws -> VaultIndexSnapshot? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return try dec.decode(VaultIndexSnapshot.self, from: Data(contentsOf: fileURL))
    }
    public func delete() throws {
        if FileManager.default.fileExists(atPath: fileURL.path) { try FileManager.default.removeItem(at: fileURL) }
    }
}

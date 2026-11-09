import Foundation
#if canImport(Darwin)
import Darwin
#endif

// Field Book Phase 2: the §3.1 surgical write path.
//
// Invariants (spec §3.1, resolves F1/C4):
// - A frontmatter edit changes the target key's line only; every other byte
//   survives — comments, unknown keys, key order, quoting, folded scalars.
//   The file is NEVER round-tripped through a YAML serializer.
// - Body edits replace the body region only.
// - Frontmatter + body land in ONE save (D13).
// - Open captures content hash + mtime; both are re-verified immediately
//   before save. Mismatch = refuse + conflict copy; the buffer is never
//   discarded and never wins by overwrite.
// - No-op save (result bytes == current bytes) skips the write entirely.
// - Unknown schema major (m3ta: 2+) is read-only: every save refuses.
// - Synced trees write through NSFileCoordinator coordinated replace;
//   local trees write-temp-then-rename in the same directory.

public struct KeyEdit: Equatable, Sendable {
    public var key: String
    public var value: String // raw scalar as it should appear after "key: " ("" renders "key:")
    public init(key: String, value: String) { self.key = key; self.value = value }
}

public struct OpenedRecord: Sendable {
    public var url: URL
    public var text: String
    public var contentHash: String
    public var mtime: Date
    public init(url: URL, text: String, contentHash: String, mtime: Date) {
        self.url = url; self.text = text; self.contentHash = contentHash; self.mtime = mtime
    }
    public var parse: FrontmatterParse { FrontmatterParser.parse(text) }
}

public enum SaveResult: Equatable, Sendable {
    case noOp
    case saved
    case conflict(conflictCopyPath: String)
    case refused(reason: String)
}

public struct VaultWriter: Sendable {
    /// Clock injection for deterministic conflict-copy names in tests.
    public var now: @Sendable () -> Date
    public init(now: @escaping @Sendable () -> Date = { Date() }) { self.now = now }

    // MARK: Open

    public func open(url: URL) throws -> OpenedRecord {
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "VaultWriter", code: 1, userInfo: [NSLocalizedDescriptionKey: "non-UTF-8 file"])
        }
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let mtime = (attrs[.modificationDate] as? Date) ?? Date(timeIntervalSince1970: 0)
        return OpenedRecord(url: url, text: text, contentHash: fieldBookHash(data), mtime: mtime)
    }

    // MARK: Pure surgical transforms (tested directly)

    /// Locate the frontmatter line range in a "\n"-split line array.
    /// Returns (openIndex=0, closeIndex) or nil when there is no complete
    /// frontmatter block — the same rule the parser uses (§2.2).
    public static func frontmatterRange(in lines: [String]) -> (open: Int, close: Int)? {
        guard let first = lines.first, first.trimmingCharacters(in: .whitespaces) == "---" else { return nil }
        for i in 1..<min(lines.count, 501) {
            let t = lines[i].trimmingCharacters(in: .whitespaces)
            if t == "---" || t == "..." { return (0, i) }
        }
        return nil
    }

    static func keyOf(line: String) -> String? {
        // Top-level keys only: not indented, not a comment, not a list item.
        if line.hasPrefix(" ") || line.hasPrefix("\t") { return nil }
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("#") || trimmed.hasPrefix("- ") { return nil }
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let key = String(line[line.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
        return key.isEmpty ? nil : key
    }

    /// Apply frontmatter key edits line-surgically. Each edit replaces the
    /// FIRST line carrying that key inside the block (duplicate keys: the
    /// later duplicates survive untouched), or inserts one new line just
    /// before the closing fence when the key is missing. Refuses (nil)
    /// when there is no complete frontmatter block.
    public static func applyKeyEdits(text: String, edits: [KeyEdit]) -> String? {
        var current = text
        for edit in edits {
            var lines = current.components(separatedBy: "\n")
            guard let range = frontmatterRange(in: lines) else { return nil }
            let rendered = edit.value.isEmpty ? "\(edit.key):" : "\(edit.key): \(edit.value)"
            var replaced = false
            for i in (range.open + 1)..<range.close where keyOf(line: lines[i]) == edit.key {
                let cr = lines[i].hasSuffix("\r") ? "\r" : ""
                lines[i] = rendered + cr
                replaced = true
                break
            }
            if !replaced { lines.insert(rendered, at: range.close) }
            current = lines.joined(separator: "\n")
        }
        return current
    }

    /// Replace the body region only; the frontmatter block (and everything
    /// through the closing fence line) is preserved byte-for-byte. A file
    /// with no frontmatter is all body.
    public static func replaceBody(text: String, newBody: String) -> String {
        let lines = text.components(separatedBy: "\n")
        guard let range = frontmatterRange(in: lines) else {
            // Unclosed frontmatter: the parser's body is everything after
            // the opening fence line — replace exactly that region so a
            // body edit can never swallow the pseudo-frontmatter lines.
            if let first = lines.first, first.trimmingCharacters(in: .whitespaces) == "---" {
                let currentBody = lines.dropFirst().joined(separator: "\n")
                if newBody == currentBody { return text }
                return lines[0] + "\n" + newBody
            }
            return newBody
        }
        let currentBody = range.close + 1 < lines.count ? lines[(range.close + 1)...].joined(separator: "\n") : ""
        if newBody == currentBody { return text }
        let prefix = lines[0...range.close].joined(separator: "\n")
        return prefix + "\n" + newBody
    }

    /// D13: frontmatter edits + body replacement composed into one result.
    public static func composeSave(text: String, edits: [KeyEdit], newBody: String?) -> String? {
        var result = text
        if !edits.isEmpty {
            guard let edited = applyKeyEdits(text: result, edits: edits) else { return nil }
            result = edited
        }
        if let newBody { result = replaceBody(text: result, newBody: newBody) }
        return result
    }

    // MARK: Validation (§2.2, before save)

    public static let tierEnum: Set<String> = ["idea", "shelf", "bench"]
    public static let ownerEnum: Set<String> = ["qb", "hermes", "orbit", "paperclip", "crm", "adam", "content-engine"]

    /// Problems that refuse a save. The schema-major rule applies to every
    /// save; value rules apply to the keys this save changes (plus `status:`
    /// re-checked against a simultaneously changed `type:`).
    public static func validationProblems(originalText: String, newText: String, changedKeys: Set<String>) -> [String] {
        var problems: [String] = []
        let newParse = FrontmatterParser.parse(newText)
        if let m = newParse.fields["m3ta"] {
            if let i = m.intValue, i > 1 { problems.append("newer schema m3ta: \(i) — record is read-only") }
            else if m.intValue == nil { problems.append("m3ta: version is not an integer") }
        }
        if newParse.error?.contains("unclosed") == true { problems.append("frontmatter is unclosed — cannot save safely") }
        let type = newParse.string("type")
        func check(_ key: String) {
            guard changedKeys.contains(key), let v = newParse.string(key) else { return }
            switch key {
            case "status":
                if let t = type, let allowed = VaultRecord.statusEnum(for: t), !allowed.contains(v) {
                    problems.append("invalid status value: \(v) for type \(t)")
                }
            case "tier":
                if !tierEnum.contains(v) { problems.append("invalid tier value: \(v)") }
            case "classification":
                if RecordClassification(rawValue: v.lowercased()) == nil { problems.append("invalid classification value: \(v)") }
            case "type":
                if !VaultRecord.typeEnum.contains(v) { problems.append("invalid type value: \(v)") }
            case "owner":
                if !v.isEmpty && !ownerEnum.contains(v) { problems.append("invalid owner value: \(v)") }
            case "due", "snooze_until", "event_date", "created", "updated":
                if !v.isEmpty && !VaultRecord.isValidLocalDate(v) { problems.append("invalid \(key) value: \(v) (expected yyyy-MM-dd)") }
            default: break
            }
        }
        for key in changedKeys { check(key) }
        if changedKeys.contains("type") && !changedKeys.contains("status") {
            // Type changed under an existing status: re-validate the pair.
            var widened = changedKeys; widened.insert("status")
            return validationProblems(originalText: originalText, newText: newText, changedKeys: widened)
        }
        _ = originalText
        return problems
    }

    // MARK: Save (§3.1 mechanism)

    /// One save: compose, validate, conflict-check, write — or refuse.
    /// `synced` selects NSFileCoordinator coordinated replace (iCloud
    /// trees) vs write-temp-then-rename (local trees).
    public func save(opened: OpenedRecord, edits: [KeyEdit], newBody: String?, synced: Bool) -> SaveResult {
        guard let newText = Self.composeSave(text: opened.text, edits: edits, newBody: newBody) else {
            return .refused(reason: "no complete frontmatter block — frontmatter edits refused (body remains editable as plain text)")
        }
        let newData = Data(newText.utf8)

        // Re-read the current file: needed for the no-op comparison, the
        // conflict check, and the write itself.
        let fm = FileManager.default
        guard let currentData = try? Data(contentsOf: opened.url),
              let attrs = try? fm.attributesOfItem(atPath: opened.url.path),
              let curMtime = attrs[.modificationDate] as? Date else {
            return .refused(reason: "file vanished or became unreadable before save")
        }

        // Zero-byte diff: the result already equals what is on disk, so
        // the write is skipped entirely — on EVERY file, including
        // malformed ones (§3.1 zero-byte-diff-on-no-op). Nothing is
        // written, so there is nothing to validate and no conflict to
        // lose: a no-op save over an externally changed file is still a
        // no-op, not an overwrite.
        if newData == currentData { return .noOp }

        // Conflict check: hash + mtime re-verified immediately before save.
        let curHash = fieldBookHash(currentData)
        if curHash != opened.contentHash || curMtime != opened.mtime {
            let copy = Self.conflictCopyURL(for: opened.url, at: now())
            do { try newData.write(to: copy) } catch {
                return .refused(reason: "conflict, and the conflict copy could not be written: \(error.localizedDescription)")
            }
            return .conflict(conflictCopyPath: copy.path)
        }

        let changedKeys = Set(edits.map(\.key))
        let problems = Self.validationProblems(originalText: opened.text, newText: newText, changedKeys: changedKeys)
        if let first = problems.first { return .refused(reason: first) }

        do {
            if synced { try Self.coordinatedReplace(url: opened.url, data: newData) }
            else { try Self.atomicReplace(url: opened.url, data: newData) }
        } catch {
            return .refused(reason: "write failed: \(error.localizedDescription)")
        }
        return .saved
    }

    /// Create a brand-new record file. Refuses if the path already exists
    /// (capture ingest creates new files only, §3.1 writer census #4).
    public func createFile(url: URL, content: String, synced: Bool) -> SaveResult {
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) { return .refused(reason: "file already exists: \(url.lastPathComponent)") }
        let parse = FrontmatterParser.parse(content)
        if let m = parse.fields["m3ta"], let i = m.intValue, i > 1 { return .refused(reason: "newer schema — refusing to create") }
        do {
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if synced {
                var coordError: NSError?
                var writeError: Error?
                NSFileCoordinator().coordinate(writingItemAt: url, options: [], error: &coordError) { actual in
                    do { try Data(content.utf8).write(to: actual, options: []) } catch { writeError = error }
                }
                if let e = writeError ?? coordError { throw e }
            } else {
                try Data(content.utf8).write(to: url, options: [])
            }
        } catch { return .refused(reason: "create failed: \(error.localizedDescription)") }
        return .saved
    }

    // MARK: Write mechanisms

    static func atomicReplace(url: URL, data: Data) throws {
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()
        let temp = dir.appendingPathComponent(".\(url.lastPathComponent).tmp-\(UUID().uuidString)")
        try data.write(to: temp, options: [])
        do { _ = try fm.replaceItemAt(url, withItemAt: temp) }
        catch { try? fm.removeItem(at: temp); throw error }
    }

    static func coordinatedReplace(url: URL, data: Data) throws {
        #if canImport(Darwin)
        var coordError: NSError?
        var innerError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: [.forReplacing], error: &coordError) { actual in
            do { try atomicReplace(url: actual, data: data) } catch { innerError = error }
        }
        if let e = innerError ?? coordError { throw e }
        #else
        try atomicReplace(url: url, data: data)
        #endif
    }

    public static func conflictCopyURL(for url: URL, at date: Date) -> URL {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "America/New_York"); f.dateFormat = "yyyyMMdd-HHmmss"
        let base = url.deletingPathExtension().lastPathComponent
        return url.deletingLastPathComponent().appendingPathComponent("\(base).conflict-\(f.string(from: date)).md")
    }

    /// Heuristic tree classification for the write mechanism: the canonical
    /// D1(a) tree lives under Mobile Documents (iCloud FileProvider).
    public static func looksSynced(_ url: URL) -> Bool {
        url.path.contains("/Mobile Documents/") || url.path.contains("iCloud~")
    }

    // MARK: Board / tier actions as pure edit computation

    /// Promote one tier step (idea → shelf → bench). A type:idea record
    /// reaching bench also gets status: promoted (§2.2 idea enum note).
    public static func promotionEdits(tierRaw: String?, typeRaw: String?) -> [KeyEdit] {
        let current = tierRaw ?? "idea"
        let next: String
        switch current {
        case "idea": next = "shelf"
        case "shelf": next = "bench"
        default: return [] // bench (or unknown) promotes no further
        }
        var edits = [KeyEdit(key: "tier", value: next)]
        if typeRaw == "idea" && next == "bench" { edits.append(KeyEdit(key: "status", value: "promoted")) }
        return edits
    }

    public static func snoozeEdit(until dateString: String) -> KeyEdit { KeyEdit(key: "snooze_until", value: dateString) }

    // MARK: Ideas capture

    public static func slug(_ title: String) -> String {
        var out = ""
        var lastDash = true // trims leading separators
        for ch in title.lowercased() {
            if ch.isLetter || ch.isNumber { out.append(ch); lastDash = false }
            else if !lastDash { out.append("-"); lastDash = true }
        }
        while out.hasSuffix("-") { out.removeLast() }
        return out.isEmpty ? "idea" : out
    }

    /// Record ID minted at creation: millisecond timestamp hex + a caller
    /// supplied entropy suffix (UUID fragment in the app, fixed in tests).
    public static func mintRecordID(now: Date, suffix: String) -> String {
        let ms = Int(now.timeIntervalSince1970 * 1000)
        return String(format: "%012llx", ms) + suffix.lowercased()
    }

    public static func captureContent(title: String, id: String, dateString: String) -> String {
        """
        ---
        m3ta: 1
        id: \(id)
        type: idea
        status: captured
        tier: idea
        classification: internal
        created: \(dateString)
        updated: \(dateString)
        ---

        # \(title)

        """
    }

    public static func localDateString(_ date: Date, timeZone: TimeZone = TimeZone(identifier: "America/New_York")!) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone; f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}

// MARK: - Boards (pure model over the index, §1.4/§2.2)

public struct BoardModel: Equatable, Sendable {
    public var columns: [(status: String, records: [VaultRecord])]
    public var unsorted: [VaultRecord]
    public var attention: [VaultRecord]
    public var offBoard: [VaultRecord]

    public static func == (a: BoardModel, b: BoardModel) -> Bool {
        a.unsorted == b.unsorted && a.attention == b.attention && a.offBoard == b.offBoard
            && a.columns.count == b.columns.count
            && zip(a.columns, b.columns).allSatisfy { $0.status == $1.status && $0.records == $1.records }
    }

    /// Off-board terminal statuses per type (§2.2: rendered "+ dropped" etc).
    static let offBoardStatuses: [String: Set<String>] = [
        "endeavor": ["dropped"], "content": ["archived"], "idea": ["discarded"],
    ]
    /// Column order is the §2.2 enum order without the off-board terminals.
    public static func columnStatuses(for type: String) -> [String] {
        guard let all = VaultRecord.statusEnum(for: type) else { return [] }
        // statusEnum is a Set; canonical order comes from the spec table.
        let order: [String]
        switch type {
        case "endeavor": order = ["inbox", "planned", "active", "blocked", "review", "done"]
        case "content": order = ["idea", "drafting", "in-production", "in-review", "approved", "scheduled", "published"]
        case "idea": order = ["captured", "triaged", "promoted"]
        default: order = all.sorted()
        }
        return order.filter { all.contains($0) }
    }

    /// Snoozed records hide from boards/Lookout through the END of their
    /// snooze_until local date (§2.2): hidden while today <= snooze_until.
    public static func isSnoozed(_ record: VaultRecord, todayString: String) -> Bool {
        guard let s = record.snoozeUntilRaw, !s.isEmpty, VaultRecord.isValidLocalDate(s) else { return false }
        return s >= todayString
    }

    public static func build(records: [VaultRecord], type: String, todayString: String,
                             brand: String? = nil, channel: String? = nil) -> BoardModel {
        var byStatus: [String: [VaultRecord]] = [:]
        var unsorted: [VaultRecord] = []
        var attention: [VaultRecord] = []
        var offBoard: [VaultRecord] = []
        let columns = columnStatuses(for: type)
        let allowed = VaultRecord.statusEnum(for: type) ?? []
        for rec in records {
            guard rec.typeRaw == type, !rec.isConflictCopy else { continue }
            if isSnoozed(rec, todayString: todayString) { continue }
            if let brand, rec.brandRaw != brand { continue }
            if let channel, rec.channelRaw != channel { continue }
            guard let status = rec.statusRaw, !status.isEmpty else { unsorted.append(rec); continue }
            if !allowed.contains(status) { attention.append(rec); continue }
            if offBoardStatuses[type]?.contains(status) == true { offBoard.append(rec); continue }
            if columns.contains(status) { byStatus[status, default: []].append(rec) }
            else { attention.append(rec) }
        }
        return BoardModel(columns: columns.map { ($0, byStatus[$0] ?? []) },
                          unsorted: unsorted, attention: attention, offBoard: offBoard)
    }
}

// MARK: - Editor support (pure)

public struct HeadingItem: Equatable, Sendable, Identifiable {
    public var level: Int
    public var text: String
    public var lineIndex: Int // 0-based within the body
    public var id: Int { lineIndex }
    public init(level: Int, text: String, lineIndex: Int) { self.level = level; self.text = text; self.lineIndex = lineIndex }
}

public enum EditorSupport {
    /// Heading outline over the body; fenced code blocks are skipped.
    public static func outline(body: String) -> [HeadingItem] {
        var out: [HeadingItem] = []
        var inFence = false
        for (i, line) in body.components(separatedBy: "\n").enumerated() {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("```") { inFence.toggle(); continue }
            if inFence { continue }
            if let level = WeekGoalsParser.headingLevelPublic(t) {
                out.append(HeadingItem(level: level, text: WeekGoalsParser.headingTextPublic(t), lineIndex: i))
            }
        }
        return out
    }

    /// Backlinks: records whose wikilinks name this record (by title or by
    /// file stem) — §1.10 backlink tracking from the structural index.
    public static func backlinks(to target: VaultRecord, in records: [VaultRecord]) -> [VaultRecord] {
        let stem = (target.relativePath as NSString).lastPathComponent.replacingOccurrences(of: ".md", with: "")
        return records.filter { rec in
            rec.relativePath != target.relativePath && !rec.isConflictCopy
                && rec.links.contains { $0 == target.title || $0 == stem }
        }
    }
}

import Foundation

// Field Book Phase 1: frontmatter parsing per spec v2 §2.2.
// The load-bearing principle: a record that fails to parse is visible
// somewhere as failed — never dropped, never guessed at, never allowed to
// crash a board. This parser is a tolerant YAML-subset reader (flat keys,
// scalars, inline + block lists). It never reserializes anything.

public enum FieldBookValue: Equatable, Sendable {
    case string(String)
    case bool(Bool)
    case int(Int)
    case list([String])
    case null

    public var stringValue: String? {
        switch self {
        case .string(let s): return s
        case .bool(let b): return b ? "true" : "false"
        case .int(let i): return String(i)
        case .list(let l): return l.joined(separator: ", ")
        case .null: return nil
        }
    }
    public var boolValue: Bool? { if case .bool(let b) = self { return b }; return nil }
    public var intValue: Int? { if case .int(let i) = self { return i }; return nil }
}

public struct FrontmatterParse: Equatable, Sendable {
    public var present: Bool = false
    public var fields: [String: FieldBookValue] = [:]
    public var fieldOrder: [String] = []
    public var body: String = ""
    /// Non-nil when the frontmatter is malformed (unclosed block, duplicate
    /// keys, unparseable line). The body remains readable as plain text.
    public var error: String? = nil

    public func string(_ key: String) -> String? { fields[key]?.stringValue }
    public func bool(_ key: String) -> Bool? { fields[key]?.boolValue }
}

public enum FrontmatterParser {
    public static func parse(_ text: String) -> FrontmatterParse {
        var result = FrontmatterParse()
        result.body = text
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        var lines = normalized.components(separatedBy: "\n")
        guard let first = lines.first, first.trimmingCharacters(in: .whitespaces) == "---" else {
            return result
        }
        result.present = true
        // Closing fence within the first 500 lines (Phase 0 census method).
        var closeIdx: Int? = nil
        for i in 1..<min(lines.count, 501) {
            let t = lines[i].trimmingCharacters(in: .whitespaces)
            if t == "---" || t == "..." { closeIdx = i; break }
        }
        guard let close = closeIdx else {
            result.error = "unclosed frontmatter block"
            result.body = lines.dropFirst().joined(separator: "\n")
            return result
        }
        let fmLines = Array(lines[1..<close])
        result.body = lines[(close + 1)...].joined(separator: "\n")
        lines = fmLines

        var listKey: String? = nil
        var errors: [String] = []
        for raw in lines {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let indented = raw.first == " " || raw.first == "\t"
            if trimmed.hasPrefix("- "), let key = listKey {
                let item = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                var items: [String] = []
                if case .list(let existing) = result.fields[key] { items = existing }
                items.append(unquote(item))
                if result.fields[key] == nil { result.fieldOrder.append(key) }
                result.fields[key] = .list(items)
                continue
            }
            if indented {
                // Folded scalar continuation / nested content from other
                // tools: tolerated, not interpreted (visible degradation
                // would be guessing; nested maps are out of the §2.2 schema).
                continue
            }
            listKey = nil
            guard let colon = raw.firstIndex(of: ":") else {
                errors.append("unparseable frontmatter line: \(trimmed)")
                continue
            }
            let key = String(raw[raw.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
            let rawValue = String(raw[raw.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty, key.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }) else {
                errors.append("invalid frontmatter key: \(key)")
                continue
            }
            if result.fields[key] != nil {
                errors.append("duplicate key: \(key)")
                continue
            }
            if rawValue.isEmpty {
                result.fields[key] = .null
                result.fieldOrder.append(key)
                listKey = key
                continue
            }
            result.fields[key] = parseScalar(rawValue)
            result.fieldOrder.append(key)
        }
        if !errors.isEmpty { result.error = errors.joined(separator: "; ") }
        return result
    }

    static func parseScalar(_ raw: String) -> FieldBookValue {
        if raw.hasPrefix("[") && raw.hasSuffix("]") {
            let inner = raw.dropFirst().dropLast()
            if inner.trimmingCharacters(in: .whitespaces).isEmpty { return .list([]) }
            return .list(inner.components(separatedBy: ",").map { unquote($0.trimmingCharacters(in: .whitespaces)) })
        }
        let lower = raw.lowercased()
        if lower == "true" { return .bool(true) }
        if lower == "false" { return .bool(false) }
        if let i = Int(raw) { return .int(i) }
        return .string(unquote(raw))
    }

    static func unquote(_ s: String) -> String {
        if s.count >= 2, (s.hasPrefix("\"") && s.hasSuffix("\"")) || (s.hasPrefix("'") && s.hasSuffix("'")) {
            return String(s.dropFirst().dropLast())
        }
        return s
    }
}

// MARK: - Record classification / schema (§2.2)

public enum RecordClassification: String, Codable, Equatable, Sendable {
    case `public`, `internal`, `private`
}

public struct VaultRecord: Codable, Equatable, Sendable, Identifiable {
    public var relativePath: String
    public var title: String
    public var recordID: String?
    public var typeRaw: String?
    public var statusRaw: String?
    public var classificationRaw: String?
    /// Effective classification, fail-closed: missing or invalid = private.
    public var classification: RecordClassification
    public var canonical: Bool
    public var schemaMajor: Int?
    public var isNewerSchema: Bool
    public var needsAttention: Bool
    public var issues: [String]
    public var updatedRaw: String?
    public var mtime: Date
    /// max(updated:, mtime) per §2.2 — external edits move the signals.
    public var effectiveUpdated: Date
    public var links: [String]
    public var contentHash: String
    public var sizeBytes: Int

    public var id: String { recordID ?? relativePath }

    /// Private records never render on the Lookout (any panel).
    public var isLookoutVisible: Bool { classification != .private }

    public init(relativePath: String, title: String, recordID: String? = nil, typeRaw: String? = nil,
                statusRaw: String? = nil, classificationRaw: String? = nil,
                classification: RecordClassification = .private, canonical: Bool = false,
                schemaMajor: Int? = nil, isNewerSchema: Bool = false, needsAttention: Bool = false,
                issues: [String] = [], updatedRaw: String? = nil, mtime: Date = Date(timeIntervalSince1970: 0),
                effectiveUpdated: Date = Date(timeIntervalSince1970: 0), links: [String] = [],
                contentHash: String = "", sizeBytes: Int = 0) {
        self.relativePath = relativePath; self.title = title; self.recordID = recordID
        self.typeRaw = typeRaw; self.statusRaw = statusRaw; self.classificationRaw = classificationRaw
        self.classification = classification; self.canonical = canonical; self.schemaMajor = schemaMajor
        self.isNewerSchema = isNewerSchema; self.needsAttention = needsAttention; self.issues = issues
        self.updatedRaw = updatedRaw; self.mtime = mtime; self.effectiveUpdated = effectiveUpdated
        self.links = links; self.contentHash = contentHash; self.sizeBytes = sizeBytes
    }

    public static let typeEnum: Set<String> = ["endeavor", "content", "idea", "partner", "research", "planning", "countdown", "canonical", "note"]
    public static func statusEnum(for type: String) -> Set<String>? {
        switch type {
        case "endeavor": return ["inbox", "planned", "active", "blocked", "review", "done", "dropped"]
        case "content": return ["idea", "drafting", "in-production", "in-review", "approved", "scheduled", "published", "archived"]
        case "idea": return ["captured", "triaged", "promoted", "discarded"]
        case "partner": return ["prospect", "confirmed", "active", "due", "delivered", "closed"]
        case "research": return ["unread", "reading", "digested", "promoted"]
        case "planning": return ["current", "superseded"]
        case "note": return ["draft", "final"]
        default: return nil // countdown (derived) and canonical (pinned/retired checked loosely)
        }
    }

    /// Build a record from a parsed file, applying the full §2.2 tolerance
    /// table + fail-closed classification.
    public static func make(relativePath: String, parse: FrontmatterParse, mtime: Date, contentHash: String, sizeBytes: Int, links: [String]) -> VaultRecord {
        var issues: [String] = []
        var needsAttention = false
        if let e = parse.error { issues.append("frontmatter: \(e)"); needsAttention = true }

        let typeRaw = parse.string("type")
        var type = "note"
        if let t = typeRaw {
            if typeEnum.contains(t) { type = t } else { issues.append("invalid type value: \(t)"); needsAttention = true }
        }
        let statusRaw = parse.string("status")
        if let s = statusRaw, let allowed = statusEnum(for: type), !allowed.contains(s) {
            issues.append("invalid status value: \(s) for type \(type)"); needsAttention = true
        }

        let classificationRaw = parse.string("classification")
        var classification: RecordClassification = .private
        if let c = classificationRaw {
            if let parsed = RecordClassification(rawValue: c.lowercased()) { classification = parsed }
            else { issues.append("invalid classification value: \(c) (treated as private)") }
        }

        var schemaMajor: Int? = nil
        var isNewer = false
        if let m = parse.fields["m3ta"] {
            if let i = m.intValue { schemaMajor = i; if i > 1 { isNewer = true; issues.append("newer schema m3ta: \(i) — read-only") } }
            else { issues.append("m3ta: version is not an integer"); needsAttention = true }
        }

        var canonical = parse.bool("canonical") ?? false
        if canonical && classification == .private {
            issues.append("canonical record is private — excluded from the Lookout canonical row")
            canonical = false
        }

        for dateKey in ["due", "snooze_until", "event_date", "created", "updated"] {
            if let v = parse.string(dateKey), !v.isEmpty, !isValidLocalDate(v) {
                issues.append("invalid \(dateKey) value: \(v) (expected yyyy-MM-dd)"); needsAttention = true
            }
        }

        let title = parse.string("title") ?? parse.string("name") ?? firstHeading(in: parse.body) ?? (relativePath as NSString).lastPathComponent
        var effective = mtime
        if let u = parse.string("updated"), let d = localDate(u) { effective = max(d, mtime) }

        return VaultRecord(relativePath: relativePath, title: title, recordID: parse.string("id"),
                           typeRaw: typeRaw, statusRaw: statusRaw, classificationRaw: classificationRaw,
                           classification: classification, canonical: canonical, schemaMajor: schemaMajor,
                           isNewerSchema: isNewer, needsAttention: needsAttention, issues: issues,
                           updatedRaw: parse.string("updated"), mtime: mtime, effectiveUpdated: effective,
                           links: links, contentHash: contentHash, sizeBytes: sizeBytes)
    }

    static func firstHeading(in body: String) -> String? {
        for line in body.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("# ") { return String(t.dropFirst(2)).trimmingCharacters(in: .whitespaces) }
        }
        return nil
    }

    static var dateFormatter: DateFormatter {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "America/New_York"); f.dateFormat = "yyyy-MM-dd"; return f
    }
    public static func isValidLocalDate(_ s: String) -> Bool { localDate(s) != nil }
    public static func localDate(_ s: String) -> Date? {
        // Strict yyyy-MM-dd (a datetime where a date is expected is the
        // §2.2 wrong-type class, not something to coerce).
        guard s.count == 10, s.filter({ $0 == "-" }).count == 2 else { return nil }
        return dateFormatter.date(from: s)
    }
}

/// FNV-1a content hash — change detection only (reconciliation), not security.
public func fieldBookHash(_ data: Data) -> String {
    var hash: UInt64 = 0xcbf29ce484222325
    for byte in data { hash ^= UInt64(byte); hash = hash &* 0x100000001b3 }
    return String(format: "%016llx", hash)
}

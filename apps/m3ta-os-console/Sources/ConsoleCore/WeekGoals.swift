import Foundation

// §1.3c week-goals parsing. The section runs from the `## Goals` heading
// to the next heading of equal-or-higher level; checkboxes inside fenced
// code blocks are ignored; a missing or renamed section renders the
// explicit not-found state — never an empty list that reads as "no goals."

public struct GoalItem: Codable, Equatable, Sendable, Identifiable {
    public var text: String
    public var done: Bool
    public var depth: Int
    public var id: String { "\(depth)-\(done)-\(text)" }
    public init(text: String, done: Bool, depth: Int) { self.text = text; self.done = done; self.depth = depth }
}

public enum WeekGoalsOutcome: Equatable, Sendable {
    case fileMissing
    case sectionMissing
    case parsed([GoalItem])

    /// The text the Lookout renders for this outcome.
    public var displayText: String {
        switch self {
        case .fileMissing: return "Week planning file not found (planning/week.md)"
        case .sectionMissing: return "Goals section not found in `week.md`"
        case .parsed(let items): return items.map { "\($0.done ? "[x]" : "[ ]") \($0.text)" }.joined(separator: "\n")
        }
    }
    public var items: [GoalItem] { if case .parsed(let i) = self { return i }; return [] }
}

public enum WeekGoalsParser {
    public static func parse(text: String) -> WeekGoalsOutcome {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var inSection = false
        var inFence = false
        var items: [GoalItem] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") { inFence.toggle(); continue }
            if inFence { continue }
            if let level = headingLevel(trimmed) {
                if !inSection {
                    if level == 2 && headingText(trimmed) == "Goals" { inSection = true }
                    continue
                } else {
                    if level <= 2 { break } // equal-or-higher heading ends the section
                    continue // deeper heading: section continues below it
                }
            }
            if inSection, let item = checkboxItem(line) { items.append(item) }
        }
        return inSection ? .parsed(items) : .sectionMissing
    }

    public static func load(from url: URL) -> WeekGoalsOutcome {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return .fileMissing }
        return parse(text: text)
    }

    // Public helpers shared with the preview renderer.
    public static func checkboxItemPublic(_ line: String) -> GoalItem? { checkboxItem(line) }
    public static func headingLevelPublic(_ trimmed: String) -> Int? { headingLevel(trimmed) }
    public static func headingTextPublic(_ trimmed: String) -> String { headingText(trimmed) }

    static func headingLevel(_ trimmed: String) -> Int? {
        guard trimmed.hasPrefix("#") else { return nil }
        var n = 0
        for ch in trimmed { if ch == "#" { n += 1 } else { break } }
        guard n >= 1, n <= 6, trimmed.count > n, trimmed[trimmed.index(trimmed.startIndex, offsetBy: n)] == " " else { return nil }
        return n
    }
    static func headingText(_ trimmed: String) -> String {
        var t = trimmed
        while t.hasPrefix("#") { t.removeFirst() }
        return t.trimmingCharacters(in: .whitespaces)
    }
    static func checkboxItem(_ line: String) -> GoalItem? {
        // ^(\s*)[-*] \[( |x|X)\]\s+(.*)$
        var idx = line.startIndex
        var spaces = 0
        while idx < line.endIndex && (line[idx] == " " || line[idx] == "\t") { spaces += (line[idx] == "\t" ? 2 : 1); idx = line.index(after: idx) }
        let rest = String(line[idx...])
        guard rest.hasPrefix("- [") || rest.hasPrefix("* [") else { return nil }
        let afterBracket = rest.dropFirst(3)
        guard let close = afterBracket.firstIndex(of: "]") else { return nil }
        let mark = afterBracket[afterBracket.startIndex..<close]
        guard mark == " " || mark == "x" || mark == "X" else { return nil }
        let text = afterBracket[afterBracket.index(after: close)...].trimmingCharacters(in: .whitespaces)
        return GoalItem(text: text, done: mark != " ", depth: spaces / 2)
    }
}

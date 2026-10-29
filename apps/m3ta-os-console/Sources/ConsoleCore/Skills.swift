import Foundation

/// M3: local skill search over SKILL.md frontmatter (name + description). Read-only.
public struct SkillEntry: Sendable, Equatable, Identifiable { public let name: String; public let summary: String; public let path: String; public var id: String { path } }

public enum SkillIndex {
    public static let defaultRoots = ["~/m3ta-os/skills-library"].map { ($0 as NSString).expandingTildeInPath }
    public static func load(roots: [String] = defaultRoots, limit: Int = 5000) -> [SkillEntry] {
        var out: [SkillEntry] = []
        for r in roots {
            guard let en = FileManager.default.enumerator(atPath: r) else { continue }
            while let rel = en.nextObject() as? String, out.count < limit {
                if rel.components(separatedBy: "/").count > 3 { en.skipDescendants(); continue }
                guard rel.hasSuffix("SKILL.md") else { continue }
                let p = (r as NSString).appendingPathComponent(rel)
                guard let s = try? String(contentsOfFile: p, encoding: .utf8) else { continue }
                out.append(parse(s, path: p))
            }
        }
        return out.sorted { $0.name < $1.name }
    }
    public static func parse(_ s: String, path: String) -> SkillEntry {
        var name = ((path as NSString).deletingLastPathComponent as NSString).lastPathComponent, desc = ""
        if s.hasPrefix("---") {
            for line in s.split(separator: "\n").dropFirst() {
                if line.hasPrefix("---") { break }
                if line.hasPrefix("name:") { name = line.dropFirst(5).trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) }
                if line.hasPrefix("description:") { desc = line.dropFirst(12).trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) }
            }
        }
        return SkillEntry(name: name, summary: String(desc.prefix(200)), path: path)
    }
    /// All query words must appear in name or summary; name hits rank first.
    public static func search(_ q: String, in all: [SkillEntry]) -> [SkillEntry] {
        let words = q.lowercased().split(separator: " ").map(String.init)
        guard !words.isEmpty else { return all }
        return all.filter { e in let h = (e.name + " " + e.summary).lowercased(); return words.allSatisfy { h.contains($0) } }
            .sorted { a, b in
                let an = words.allSatisfy { a.name.lowercased().contains($0) }, bn = words.allSatisfy { b.name.lowercased().contains($0) }
                return an != bn ? an : a.name < b.name
            }
    }
}

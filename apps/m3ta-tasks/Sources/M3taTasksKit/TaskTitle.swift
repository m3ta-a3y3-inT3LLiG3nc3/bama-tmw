import Foundation

/// Rules for task titles. Logic lives in this library so tests can run it
/// without the app. Put parsers, date rules, and data rules here too.
public enum TaskTitle {
    /// Trims spaces and line breaks, collapses inner runs of spaces, and
    /// falls back to "New Task" for an empty title.
    public static func clean(_ text: String) -> String {
        let words = text.split(whereSeparator: \.isWhitespace)
        return words.isEmpty ? "New Task" : words.joined(separator: " ")
    }
}

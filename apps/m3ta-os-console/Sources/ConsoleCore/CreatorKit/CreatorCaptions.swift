#if os(macOS) || os(iOS)
import Foundation
import Speech

/// Captions: on-device Speech → word timings → caption cues → SRT. (whisper.cpp output can feed `cues` too.)
public struct CaptionWord: Sendable, Equatable { public let text: String; public let start: Double; public let duration: Double
    public init(_ text: String, _ start: Double, _ duration: Double) { self.text = text; self.start = start; self.duration = duration } }
public struct CaptionCue: Sendable, Equatable { public let start: Double; public let end: Double; public let text: String
    public init(start: Double, end: Double, text: String) { self.start = start; self.end = end; self.text = text } }

public enum CreatorCaptions {
    /// Group words into cues of at most `maxChars` and `maxSeconds`, breaking on long pauses.
    public static func cues(_ words: [CaptionWord], maxChars: Int = 42, maxSeconds: Double = 5, pause: Double = 0.8) -> [CaptionCue] {
        var out: [CaptionCue] = []; var cur: [CaptionWord] = []
        func flush() { if let f = cur.first, let l = cur.last { out.append(CaptionCue(start: f.start, end: l.start + l.duration, text: cur.map(\.text).joined(separator: " "))) }; cur = [] }
        for w in words {
            if let f = cur.first, let l = cur.last {
                let text = (cur.map(\.text) + [w.text]).joined(separator: " ")
                if text.count > maxChars || w.start + w.duration - f.start > maxSeconds || w.start - (l.start + l.duration) > pause { flush() }
            }
            cur.append(w)
        }
        flush(); return out
    }
    public static func timestamp(_ t: Double) -> String {
        let ms = Int((max(0, t) * 1000).rounded()); return String(format: "%02d:%02d:%02d,%03d", ms / 3_600_000, ms / 60_000 % 60, ms / 1000 % 60, ms % 1000)
    }
    public static func srt(_ cues: [CaptionCue]) -> String {
        cues.enumerated().map { "\($0.offset + 1)\n\(timestamp($0.element.start)) --> \(timestamp($0.element.end))\n\($0.element.text)\n" }.joined(separator: "\n")
    }
    /// On-device transcription (requiresOnDeviceRecognition; never sent to a server). Needs Speech permission.
    public static func transcribe(_ url: URL, locale: Locale = Locale(identifier: "en-US")) async throws -> [CaptionWord] {
        guard let rec = SFSpeechRecognizer(locale: locale), rec.supportsOnDeviceRecognition else { throw CreatorKitError.exportFailed("on-device speech not available for \(locale.identifier)") }
        let req = SFSpeechURLRecognitionRequest(url: url); req.requiresOnDeviceRecognition = true; req.shouldReportPartialResults = false
        return try await withCheckedThrowingContinuation { (k: CheckedContinuation<[CaptionWord], Error>) in
            nonisolated(unsafe) var done = false
            rec.recognitionTask(with: req) { r, e in
                if done { return }
                if let e { done = true; k.resume(throwing: e); return }
                if let r, r.isFinal { done = true; k.resume(returning: r.bestTranscription.segments.map { CaptionWord($0.substring, $0.timestamp, $0.duration) }) }
            }
        }
    }
}
#endif

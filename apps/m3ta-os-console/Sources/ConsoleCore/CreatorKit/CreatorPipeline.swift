#if os(macOS) || os(iOS)
import Foundation

/// The creator pipeline as data: each stage has a native rebuild (CreatorKit) and a driven Apple app (via rea-mcp, gated).
public enum CreatorStage: String, CaseIterable, Sendable, Identifiable {
    case edit, thumbnails, voice, captions, export, publish
    public var id: String { rawValue }
    public var app: String { switch self { case .edit: "Final Cut Pro"; case .thumbnails: "Pixelmator Pro"; case .voice: "Voicebox → Logic Pro"; case .captions: "Speech (on-device) / whisper.cpp"; case .export: "Compressor"; case .publish: "Postiz (drafts only)" } }
    public var native: String { switch self { case .edit: "AVFoundation trim/concat"; case .thumbnails: "Core Image + Vision crop"; case .voice: "AVAudioEngine normalize"; case .captions: "Speech → SRT"; case .export: "AVAssetExportSession"; case .publish: "— (Postiz only)" } }
    public var reaTool: String? { switch self { case .edit: "rea_fcpxml_build"; case .thumbnails: "rea_pixelmator_run"; case .voice: "rea_shortcuts_run"; case .captions: nil; case .export: "rea_compressor_encode"; case .publish: "rea_postiz_draft" } }
}

/// A creator action BAMA may only QUEUE (rea-mcp holds it for the coach's approval).
public enum CreatorAction: Sendable, Equatable {
    case fcpxmlImport(title: String, clips: [ClipRange], path: String)
    case compressorEncode(source: String, setting: String, location: String)
    case pixelmatorThumbnail(input: String, output: String, width: Int, height: Int)
    case shortcut(name: String, input: String?)
    case postizDraft(content: String, integrations: [String])

    public var tool: String { switch self { case .fcpxmlImport: "rea_fcpxml_build"; case .compressorEncode: "rea_compressor_encode"; case .pixelmatorThumbnail: "rea_pixelmator_run"; case .shortcut: "rea_shortcuts_run"; case .postizDraft: "rea_postiz_draft" } }
    public var args: [String: Any] {
        switch self {
        case let .fcpxmlImport(t, c, p): ["title": t, "path": p, "clips": c.map { ["path": $0.url.path, "start": $0.start, "duration": $0.duration] }]
        case let .compressorEncode(s, set, l): ["source": s, "setting": set, "location": l, "batch": "BAMA"]
        case let .pixelmatorThumbnail(i, o, w, h): ["op": "export_thumbnail", "input": i, "output": o, "width": w, "height": h]
        case let .shortcut(n, i): i.map { ["name": n, "input": $0] } ?? ["name": n]
        case let .postizDraft(c, ids): ["content": c, "integrations": ids]
        }
    }
    public var summary: String {
        switch self {
        case let .fcpxmlImport(t, c, _): "Open “\(t)” (\(c.count) clips) in Final Cut Pro"
        case let .compressorEncode(s, _, _): "Compressor export of \((s as NSString).lastPathComponent)"
        case let .pixelmatorThumbnail(_, o, w, h): "Pixelmator thumbnail \(w)×\(h) → \((o as NSString).lastPathComponent)"
        case let .shortcut(n, _): "Run Shortcut “\(n)”"
        case let .postizDraft(c, _): "Postiz DRAFT: \(c.prefix(60))"
        }
    }
}

/// Swift twin of rea-mcp's FCPXML builder (for preview in BAMA; the import itself is gated through rea-mcp).
public enum FCPXML {
    public static func time(_ s: Double, fps: Int = 30) -> String { "\(Int((s * Double(fps) * 100).rounded()))/\(fps * 100)s" }
    static func esc(_ s: String) -> String { s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;") }
    public static func build(title: String, clips: [ClipRange], fps: Int = 30, width: Int = 1920, height: Int = 1080) -> String {
        var off = 0.0; var assets: [String] = []; var spine: [String] = []
        for (i, c) in clips.enumerated() {
            let id = "r\(i + 2)", nm = esc(c.url.lastPathComponent)
            assets.append("    <asset id=\"\(id)\" name=\"\(nm)\" start=\"0s\" duration=\"\(time(c.start + c.duration, fps: fps))\" hasVideo=\"1\" hasAudio=\"1\" format=\"r1\"><media-rep kind=\"original-media\" src=\"\(esc(c.url.absoluteString))\"/></asset>")
            spine.append("          <asset-clip ref=\"\(id)\" name=\"\(nm)\" offset=\"\(time(off, fps: fps))\" start=\"\(time(c.start, fps: fps))\" duration=\"\(time(c.duration, fps: fps))\"/>")
            off += c.duration
        }
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE fcpxml>
        <fcpxml version="1.11">
          <resources>
            <format id="r1" name="FFVideoFormat\(height)p\(fps)" frameDuration="100/\(fps * 100)s" width="\(width)" height="\(height)"/>
        \(assets.joined(separator: "\n"))
          </resources>
          <library>
            <event name="BAMA">
              <project name="\(esc(title))">
                <sequence format="r1" duration="\(time(off, fps: fps))" tcStart="0s" tcFormat="NDF">
                  <spine>
        \(spine.joined(separator: "\n"))
                  </spine>
                </sequence>
              </project>
            </event>
          </library>
        </fcpxml>

        """
    }
}

/// Queues creator actions through ReaMcpClient only. Never runs them; returns held approval ids.
public struct CreatorQueue: Sendable {
    let rea: ReaMcpClient
    public init(rea: ReaMcpClient) { self.rea = rea }
    public func enqueue(_ a: CreatorAction) async throws -> String { try await rea.queue(a.tool, a.args) }
}
#endif

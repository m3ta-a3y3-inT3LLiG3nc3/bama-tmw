#if os(macOS) || os(iOS)
import AVFoundation
import Foundation

/// CreatorKit — native rebuilds of the creator pipeline (no app automation needed). $0, on-device.
public enum CreatorKitError: Error, Equatable, LocalizedError {
    case noVideo, badRange, exportFailed(String), noAudio, image(String)
    public var errorDescription: String? {
        switch self {
        case .noVideo: "no video track"; case .badRange: "trim range is outside the clip"
        case .exportFailed(let m): "export failed: \(m)"; case .noAudio: "no audio"; case .image(let m): "image: \(m)"
        }
    }
}

public struct ClipRange: Sendable, Equatable {
    public let url: URL; public let start: Double; public let duration: Double
    public init(url: URL, start: Double = 0, duration: Double) { self.url = url; self.start = start; self.duration = duration }
}

public enum CreatorMedia {
    static let ts: CMTimeScale = 600
    /// Build a composition of back-to-back ranges (trim = a single range; concat = many).
    public static func compose(_ clips: [ClipRange]) async throws -> AVMutableComposition {
        let comp = AVMutableComposition()
        guard let v = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { throw CreatorKitError.noVideo }
        var a: AVMutableCompositionTrack?
        var cursor = CMTime.zero
        for c in clips {
            let asset = AVURLAsset(url: c.url)
            let dur = try await asset.load(.duration).seconds
            guard c.start >= 0, c.duration > 0, c.start + c.duration <= dur + 0.001 else { throw CreatorKitError.badRange }
            let range = CMTimeRange(start: CMTime(seconds: c.start, preferredTimescale: ts), duration: CMTime(seconds: c.duration, preferredTimescale: ts))
            guard let src = try await asset.loadTracks(withMediaType: .video).first else { throw CreatorKitError.noVideo }
            try v.insertTimeRange(range, of: src, at: cursor)
            if cursor == .zero { v.preferredTransform = try await src.load(.preferredTransform) }
            if let sa = try await asset.loadTracks(withMediaType: .audio).first {
                if a == nil { a = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) }
                try a?.insertTimeRange(range, of: sa, at: cursor)
            }
            cursor = cursor + range.duration
        }
        return comp
    }
    public static func trim(_ url: URL, start: Double, duration: Double) async throws -> AVMutableComposition { try await compose([ClipRange(url: url, start: start, duration: duration)]) }

    /// Export with AVAssetExportSession (the Compressor fallback). Overwrites `to`.
    public static func export(_ asset: AVAsset, to: URL, preset: String = AVAssetExportPresetHighestQuality, type: AVFileType = .mov) async throws {
        try? FileManager.default.removeItem(at: to)
        guard let s = AVAssetExportSession(asset: asset, presetName: preset) else { throw CreatorKitError.exportFailed("preset \(preset)") }
        do { try await s.export(to: to, as: type) } catch { throw CreatorKitError.exportFailed(error.localizedDescription) }
    }
}
#endif

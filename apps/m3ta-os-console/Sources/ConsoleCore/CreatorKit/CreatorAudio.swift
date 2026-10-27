#if os(macOS) || os(iOS)
import AVFoundation
import Foundation

/// Audio: peak-normalize with AVAudioEngine offline manual rendering (player → EQ global gain → output node, no mixer pan law). Logic Pro fallback.
public enum CreatorAudio {
    public static func peak(_ url: URL) throws -> Float {
        let f = try AVAudioFile(forReading: url)
        guard let buf = AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: 32768) else { throw CreatorKitError.noAudio }
        var p: Float = 0
        while f.framePosition < f.length {
            try f.read(into: buf)
            guard let ch = buf.floatChannelData else { throw CreatorKitError.noAudio }
            for c in 0..<Int(buf.format.channelCount) { for i in 0..<Int(buf.frameLength) { p = max(p, abs(ch[c][i])) } }
        }
        return p
    }
    public static func gainDB(peak: Float, targetDBFS: Float) -> Float { peak > 0 ? targetDBFS - 20 * log10(peak) : 0 }

    /// Normalize so the peak hits `targetDBFS` (default -1). Writes a CAF/WAV at `to`. Returns applied gain (dB).
    @discardableResult
    public static func normalize(_ input: URL, to output: URL, targetDBFS: Float = -1) throws -> Float {
        let gain = min(24, max(-96, gainDB(peak: try peak(input), targetDBFS: targetDBFS)))
        let file = try AVAudioFile(forReading: input)
        let fmt = file.processingFormat
        let engine = AVAudioEngine(), player = AVAudioPlayerNode(), eq = AVAudioUnitEQ(numberOfBands: 0)
        eq.globalGain = gain
        try engine.enableManualRenderingMode(.offline, format: fmt, maximumFrameCount: 4096)
        engine.attach(player); engine.attach(eq)
        engine.connect(player, to: eq, format: fmt); engine.connect(eq, to: engine.outputNode, format: fmt)
        try engine.start(); player.scheduleFile(file, at: nil); player.play()
        try? FileManager.default.removeItem(at: output)
        let out = try AVAudioFile(forWriting: output, settings: fmt.settings, commonFormat: fmt.commonFormat, interleaved: fmt.isInterleaved)
        guard let buf = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: engine.manualRenderingMaximumFrameCount) else { throw CreatorKitError.noAudio }
        while engine.manualRenderingSampleTime < file.length {
            let n = min(AVAudioFrameCount(file.length - engine.manualRenderingSampleTime), buf.frameCapacity)
            switch try engine.renderOffline(n, to: buf) {
            case .success: try out.write(from: buf)
            case .error: throw CreatorKitError.exportFailed("render")
            default: continue
            }
        }
        player.stop(); engine.stop()
        return gain
    }
}
#endif

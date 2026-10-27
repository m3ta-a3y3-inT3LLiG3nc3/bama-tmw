import Testing
import Foundation
import AVFoundation
import CoreImage
import CoreVideo
@testable import ConsoleCore

enum Fixture {
    static func tmp(_ name: String) -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("creatorkit-\(UUID().uuidString.prefix(6))-\(name)") }
    /// Solid-color H.264 clip, `seconds` long at 30 fps, 320x180.
    static func video(seconds: Int, gray: UInt8 = 128) async throws -> URL {
        let url = tmp("v.mov")
        let w = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 320, AVVideoHeightKey: 180])
        let ad = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: 320, kCVPixelBufferHeightKey as String: 180])
        w.add(input); w.startWriting(); w.startSession(atSourceTime: .zero)
        for f in 0..<(seconds * 30) {
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 2_000_000) }
            var pb: CVPixelBuffer?; CVPixelBufferPoolCreatePixelBuffer(nil, ad.pixelBufferPool!, &pb)
            CVPixelBufferLockBaseAddress(pb!, []); memset(CVPixelBufferGetBaseAddress(pb!), Int32(gray), CVPixelBufferGetDataSize(pb!)); CVPixelBufferUnlockBaseAddress(pb!, [])
            ad.append(pb!, withPresentationTime: CMTime(value: CMTimeValue(f), timescale: 30))
        }
        input.markAsFinished(); await w.finishWriting()
        return url
    }
    static func sine(amplitude: Float, seconds: Double = 1) throws -> URL {
        let url = tmp("s.caf"); let fmt = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        let f = try AVAudioFile(forWriting: url, settings: fmt.settings)
        let n = AVAudioFrameCount(44100 * seconds); let b = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: n)!; b.frameLength = n
        for i in 0..<Int(n) { b.floatChannelData![0][i] = amplitude * sin(2 * .pi * 440 * Float(i) / 44100) }
        try f.write(from: b); return url
    }
}

@Suite(.serialized) struct CreatorKitTests {
    @Test func trimConcatAndExport() async throws {
        let a = try await Fixture.video(seconds: 3), b = try await Fixture.video(seconds: 2, gray: 30)
        let t = try await CreatorMedia.trim(a, start: 0.5, duration: 1.5)
        #expect(abs(try await t.load(.duration).seconds - 1.5) < 0.05)
        let c = try await CreatorMedia.compose([ClipRange(url: a, duration: 3), ClipRange(url: b, start: 1, duration: 1)])
        #expect(abs(try await c.load(.duration).seconds - 4) < 0.05)
        await #expect(throws: CreatorKitError.badRange) { try await CreatorMedia.trim(a, start: 2, duration: 5) }
        let out = Fixture.tmp("out.mov")
        try await CreatorMedia.export(c, to: out)
        #expect(abs(try await AVURLAsset(url: out).load(.duration).seconds - 4) < 0.1)
    }
    @Test func thumbnailCropAndRender() throws {
        let r = CreatorThumbnail.cropRect(extent: CGRect(x: 0, y: 0, width: 1000, height: 1000), aspect: 16.0 / 9.0, focus: CGPoint(x: 0.5, y: 0.95))
        #expect(r.width == 1000 && r.height == 563 && r.maxY == 1000)
        let ctx = CIContext()
        let img = CIImage(color: CIColor(red: 0.1, green: 0.1, blue: 0.1)).cropped(to: CGRect(x: 0, y: 0, width: 800, height: 800))
        let cg = ctx.createCGImage(img, from: img.extent)!
        let th = try CreatorThumbnail.make(from: cg, width: 640, height: 360)
        #expect(th.width == 640 && th.height == 360)
        let url = Fixture.tmp("t.png"); try CreatorThumbnail.writePNG(th, to: url)
        #expect(try CreatorThumbnail.load(url).width == 640)
    }
    @Test func captionsToSRT() {
        let w = [CaptionWord("Welcome", 0, 0.4), CaptionWord("to", 0.45, 0.1), CaptionWord("BAMA", 0.6, 0.5), CaptionWord("Next", 2.5, 0.3), CaptionWord("line", 2.85, 0.3)]
        let c = CreatorCaptions.cues(w)
        #expect(c.count == 2 && c[0].text == "Welcome to BAMA" && c[1].start == 2.5)
        #expect(CreatorCaptions.timestamp(3725.5) == "01:02:05,500")
        let s = CreatorCaptions.srt(c)
        #expect(s.hasPrefix("1\n00:00:00,000 --> 00:00:01,100\nWelcome to BAMA\n\n2\n00:00:02,500 --> 00:00:03,150\nNext line\n"))
        #expect(CreatorCaptions.cues((0..<20).map { CaptionWord("word\($0)", Double($0) * 0.3, 0.25) }, maxChars: 20).allSatisfy { $0.text.count <= 20 })
    }
    @Test func normalizeAudio() throws {
        let src = try Fixture.sine(amplitude: 0.25)
        #expect(abs(try CreatorAudio.peak(src) - 0.25) < 0.01)
        let out = Fixture.tmp("n.caf")
        let g = try CreatorAudio.normalize(src, to: out, targetDBFS: -1)
        #expect(abs(g - 11.04) < 0.1)
        let p = try CreatorAudio.peak(out); #expect(abs(p - 0.891) < 0.02, "peak \(p)")
    }
    @Test func fcpxmlAndActions() {
        let x = FCPXML.build(title: "A & B", clips: [ClipRange(url: URL(fileURLWithPath: "/Users/k/a.mov"), duration: 2), ClipRange(url: URL(fileURLWithPath: "/Users/k/c.mov"), start: 1, duration: 3)])
        #expect(x.contains("<fcpxml version=\"1.11\">") && x.contains("A &amp; B") && x.contains("offset=\"6000/3000s\" start=\"3000/3000s\" duration=\"9000/3000s\""))
        let a = CreatorAction.postizDraft(content: "hello", integrations: ["x"])
        #expect(a.tool == "rea_postiz_draft" && (a.args["content"] as? String) == "hello")
        #expect(CreatorStage.allCases.compactMap(\.reaTool).allSatisfy { ReaMcpClient.gatedTools.contains($0) })
    }
    @Test func queueOnlyHoldsNeverRuns() async throws {
        let t = FakeTransport()
        t.responses["rea_postiz_draft"] = (#"{"jsonrpc":"2.0","id":1,"result":{"structuredContent":{"ok":true,"status":"awaiting_approval","approval":{"id":"ap-1"}}}}"#, 200)
        t.responses["rea_compressor_encode"] = (#"{"jsonrpc":"2.0","id":1,"result":{"structuredContent":{"ok":true,"status":"done"}}}"#, 200)
        let q = CreatorQueue(rea: ReaMcpClient.mac(transport: t))
        #expect(try await q.enqueue(.postizDraft(content: "hi", integrations: [])) == "ap-1")
        await #expect(throws: (any Error).self) { try await q.enqueue(.compressorEncode(source: "/a", setting: "/b", location: "/c")) }
        await #expect(throws: ReaMcpError.notReadOnly("rea_orbit_message")) { try await ReaMcpClient.mac(transport: t).queue("rea_orbit_message", [:]) }
        await #expect(throws: (any Error).self) { try await ReaMcpClient.mac(transport: t).queue("rea_fcpxml_build", ["clips": []]) }
    }
}

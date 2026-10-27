#if os(macOS) || os(iOS)
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

/// Thumbnails: saliency-aware crop (Vision) → scale (Core Image) → PNG. Pixelmator Pro fallback.
public enum CreatorThumbnail {
    /// Largest rect of `aspect` inside `extent`, centered on `focus` (normalized, origin bottom-left) and clamped.
    public static func cropRect(extent: CGRect, aspect: Double, focus: CGPoint = CGPoint(x: 0.5, y: 0.5)) -> CGRect {
        var w = extent.width, h = w / aspect
        if h > extent.height { h = extent.height; w = h * aspect }
        var x = extent.minX + focus.x * extent.width - w / 2, y = extent.minY + focus.y * extent.height - h / 2
        x = min(max(x, extent.minX), extent.maxX - w); y = min(max(y, extent.minY), extent.maxY - h)
        return CGRect(x: x, y: y, width: w, height: h).integral.intersection(extent)
    }
    /// Center of the most salient region (Vision attention saliency); nil if Vision finds nothing.
    public static func saliencyFocus(_ cg: CGImage) -> CGPoint? {
        let req = VNGenerateAttentionBasedSaliencyImageRequest()
        guard (try? VNImageRequestHandler(cgImage: cg).perform([req])) != nil,
              let box = (req.results?.first?.salientObjects ?? []).max(by: { $0.confidence < $1.confidence })?.boundingBox else { return nil }
        return CGPoint(x: box.midX, y: box.midY)
    }
    public static func make(from cg: CGImage, width: Int = 1280, height: Int = 720, useSaliency: Bool = true) throws -> CGImage {
        let img = CIImage(cgImage: cg)
        let focus = useSaliency ? (saliencyFocus(cg) ?? CGPoint(x: 0.5, y: 0.5)) : CGPoint(x: 0.5, y: 0.5)
        let r = cropRect(extent: img.extent, aspect: Double(width) / Double(height), focus: focus)
        let cropped = img.cropped(to: r).transformed(by: CGAffineTransform(translationX: -r.minX, y: -r.minY))
        let scaled = cropped.transformed(by: CGAffineTransform(scaleX: CGFloat(width) / r.width, y: CGFloat(height) / r.height))
        guard let out = CIContext().createCGImage(scaled, from: CGRect(x: 0, y: 0, width: width, height: height)) else { throw CreatorKitError.image("render") }
        return out
    }
    public static func load(_ url: URL) throws -> CGImage {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil), let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { throw CreatorKitError.image("cannot read \(url.lastPathComponent)") }
        return cg
    }
    public static func writePNG(_ cg: CGImage, to url: URL) throws {
        guard let d = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { throw CreatorKitError.image("dest") }
        CGImageDestinationAddImage(d, cg, nil)
        guard CGImageDestinationFinalize(d) else { throw CreatorKitError.image("write") }
    }
}
#endif

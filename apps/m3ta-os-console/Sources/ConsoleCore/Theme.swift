import Foundation

/// M3ta house tokens, traced to the disk brand kits (00-INDEX / a3y3-lab: navy #001635 · gold #C58E33 · white · titanium; system font).
/// Titanium has no ratified hex, so it maps to the system secondary/gray. No invented hex values.
public enum M3taTokens {
    public static let navyHex = 0x001635
    public static let goldHex = 0xC58E33
    public static let whiteHex = 0xFFFFFF
    public enum Spacing { public static let xs: Double = 4, s: Double = 8, m: Double = 12, l: Double = 16, xl: Double = 24 }
    public enum Radius { public static let tile: Double = 14, chip: Double = 8 }

    public static func rgb(_ hex: Int) -> (Double, Double, Double) {
        (Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255)
    }
    static func lin(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
    public static func luminance(_ hex: Int) -> Double { let (r, g, b) = rgb(hex); return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b) }
    /// WCAG 2.x contrast ratio.
    public static func contrast(_ a: Int, _ b: Int) -> Double {
        let (x, y) = (luminance(a), luminance(b)); return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }
}

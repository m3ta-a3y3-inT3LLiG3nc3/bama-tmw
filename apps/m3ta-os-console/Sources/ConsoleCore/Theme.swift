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

/// TMW Cosmic Lightbody v1 (bama-theme pack, 2026-10-27; source Resources/theme/tokens.json).
/// Semantic light ("Lightbody Day") and dark (onyx) palettes. Dark is the default.
/// Rules: cosmic-red-deep / violet-deep are never text on onyx; never red on violet or violet on red.
public enum TMWTokens {
    public struct Palette: Sendable, Equatable {
        public let bg, surface, line, text, textMuted, accent, accentFill, onAccent, accent2, link, glow, success, alert: Int
        /// Text-bearing pairs that must meet WCAG AA (4.5:1).
        public var textPairs: [(String, Int, Int)] {
            [("text/bg", text, bg), ("text/surface", text, surface), ("muted/bg", textMuted, bg), ("muted/surface", textMuted, surface),
             ("accent/bg", accent, bg), ("onAccent/accentFill", onAccent, accentFill), ("link/bg", link, bg), ("link/surface", link, surface),
             ("success/bg", success, bg), ("alert/bg", alert, bg)]
        }
    }
    public static let onyx = 0x0E0A12, onyxRaised = 0x1B1422, cosmicRed = 0xF0505A, cosmicRedDeep = 0xA01628,
                      violetGlow = 0xB48CF2, violetDeep = 0x5B2C9E, lightbody = 0xFBF6EE, pearl = 0xEDE4F5
    public static let light = Palette(bg: 0xFBF6EE, surface: 0xFFFFFF, line: 0xE2D8E6, text: 0x0E0A12, textMuted: 0x5A5064,
        accent: 0xA01628, accentFill: 0xA01628, onAccent: 0xFBF6EE, accent2: 0x5B2C9E, link: 0x5B2C9E, glow: 0xEDE4F5, success: 0x1F6B45, alert: 0xA3261C)
    public static let dark = Palette(bg: 0x0E0A12, surface: 0x1B1422, line: 0x3A2C48, text: 0xFBF6EE, textMuted: 0xBDB2C8,
        accent: 0xF0505A, accentFill: 0xF0505A, onAccent: 0x0E0A12, accent2: 0xB48CF2, link: 0xB48CF2, glow: 0xB48CF2, success: 0x5CC08E, alert: 0xFF9F6B)
}

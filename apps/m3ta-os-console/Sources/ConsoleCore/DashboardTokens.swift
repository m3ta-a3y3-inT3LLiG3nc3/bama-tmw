import Foundation

/// Dashboard token set, system 1: the updated Th3 M3ta Way brand kit
/// (gold #C9A227 on deep black), completed per the dashboard spec's
/// token-completion step (docs/designs/m3ta-way-dashboard-2026-11-02.md,
/// Brand application). The kit itself supplies only bg, surface, and the
/// two golds; the remaining slots below are DESIGNED proposals from the
/// 2026-11-02 dashboard build, labeled as such, and each text-bearing
/// pair passes WCAG AA (verified in DashboardThemeTests, ThemeTests
/// style). System 1 is a dark system: the dashboard renders this palette
/// in both appearances rather than inventing a light variant the kit
/// does not define.
///
/// Status colors come from the semantic slots (success / accent2 /
/// alert / bad), never from the brand accent alone; the mapping lives in
/// `DashboardStatus`.
public enum DashboardTokens {
    public struct Palette: Sendable, Equatable {
        public let bg, surface, line, text, textMuted, accent, accentFill, onAccent, accent2, link, glow, success, alert, bad: Int
        /// Text-bearing pairs that must meet WCAG AA (4.5:1).
        public var textPairs: [(String, Int, Int)] {
            [("text/bg", text, bg), ("text/surface", text, surface),
             ("muted/bg", textMuted, bg), ("muted/surface", textMuted, surface),
             ("accent/bg", accent, bg), ("accent/surface", accent, surface),
             ("accent2/bg", accent2, bg), ("accent2/surface", accent2, surface),
             ("onAccent/accentFill", onAccent, accentFill),
             ("link/bg", link, bg), ("link/surface", link, surface),
             ("success/bg", success, bg), ("success/surface", success, surface),
             ("alert/bg", alert, bg), ("alert/surface", alert, surface),
             ("bad/bg", bad, bg), ("bad/surface", bad, surface)]
        }
    }

    /// From the brand kit (verified in the shipped Digital HQ surface and
    /// the brand-kit spec): bg #0A0A0C, surface #121214, gold #C9A227,
    /// accent gold #E6C65C.
    public static let kitBg = 0x0A0A0C, kitSurface = 0x121214, kitGold = 0xC9A227, kitGoldAccent = 0xE6C65C

    /// Designed completion slots (proposals, 2026-11-02): warm off-white
    /// text, warm gray muted text, hairline, and the three semantic
    /// status slots (success/alert match the TMW dark semantic tokens;
    /// bad is the TMW cosmic red, the only red on record that passes AA
    /// on these backgrounds).
    public static let standard = Palette(
        bg: kitBg, surface: kitSurface, line: 0x2C2A26,
        text: 0xF5EFE0, textMuted: 0xA79E8D,
        accent: kitGold, accentFill: kitGold, onAccent: kitBg,
        accent2: kitGoldAccent, link: kitGoldAccent, glow: kitGold,
        success: 0x5CC08E, alert: 0xFF9F6B, bad: 0xF0505A)
}

/// The dashboard's status vocabulary. One capsule per source block; a
/// panel never averages two states into one word. A state word outside
/// the vocabulary renders raw, in the `StatusTag` manner.
public enum DashboardStatus: Sendable, Equatable {
    case live, snapshot, designed, blocked
    case raw(String)

    public init(word: String) {
        switch word.lowercased() {
        case "live": self = .live
        case "snapshot": self = .snapshot
        case "designed": self = .designed
        case "blocked": self = .blocked
        default: self = .raw(word)
        }
    }

    /// The word as rendered on the capsule.
    public var word: String {
        switch self {
        case .live: return "live"
        case .snapshot: return "snapshot"
        case .designed: return "designed"
        case .blocked: return "blocked"
        case .raw(let w): return w
        }
    }

    /// Semantic slot in the token palette (a hex), by slot, never by
    /// brand accent: live -> success, snapshot -> accent2,
    /// designed -> alert, blocked -> bad, raw -> textMuted.
    public var slotHex: Int {
        let p = DashboardTokens.standard
        switch self {
        case .live: return p.success
        case .snapshot: return p.accent2
        case .designed: return p.alert
        case .blocked: return p.bad
        case .raw: return p.textMuted
        }
    }

    /// Sort rank for Panel 4's deterministic ordering: blocked first,
    /// then snapshot, then designed, then live, raw last.
    public var sortRank: Int {
        switch self {
        case .blocked: return 0
        case .snapshot: return 1
        case .designed: return 2
        case .live: return 3
        case .raw: return 4
        }
    }
}

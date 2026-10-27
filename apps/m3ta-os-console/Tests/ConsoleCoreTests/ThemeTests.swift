import Testing
@testable import ConsoleCore

@Suite struct ThemeTests {
    @Test func tokensMatchKit() {
        #expect(M3taTokens.navyHex == 0x001635)
        #expect(M3taTokens.goldHex == 0xC58E33)
    }
    @Test func contrastPairsPassAA() {
        #expect(M3taTokens.contrast(M3taTokens.whiteHex, M3taTokens.navyHex) >= 4.5)
        #expect(M3taTokens.contrast(M3taTokens.goldHex, M3taTokens.navyHex) >= 4.5)
        // Gold on white is below 4.5:1, so gold is never used as body text on light surfaces (accent fills only).
        #expect(M3taTokens.contrast(M3taTokens.goldHex, M3taTokens.whiteHex) < 4.5)
    }
}

@Suite struct TMWThemeTests {
    @Test func lightPairsPassAA() { for (n, a, b) in TMWTokens.light.textPairs { #expect(M3taTokens.contrast(a, b) >= 4.5, "light \(n)") } }
    @Test func darkPairsPassAA() { for (n, a, b) in TMWTokens.dark.textPairs { #expect(M3taTokens.contrast(a, b) >= 4.5, "dark \(n)") } }
    @Test func fillOnlyTokensFailAsTextOnOnyx() {
        // Documents the pack rule: these are fills, never text on onyx.
        #expect(M3taTokens.contrast(TMWTokens.cosmicRedDeep, TMWTokens.onyx) < 4.5)
        #expect(M3taTokens.contrast(TMWTokens.violetDeep, TMWTokens.onyx) < 4.5)
        #expect(M3taTokens.contrast(TMWTokens.cosmicRed, TMWTokens.violetGlow) < 4.5)
    }
}

@Suite struct KenteThemeTests {
    static let lightBgs = [TMWTokens.light.bg, TMWTokens.light.surface, TMWTokens.lightbody, TMWTokens.pearl, 0xFFFFFF]
    @Test func goldTextNeverOnLight() {
        #expect(KenteTokens.goldText(onDark: false) != KenteTokens.gold)
        for (n, fg, bg) in KenteTokens.textPairs where Self.lightBgs.contains(bg) {
            #expect(fg != KenteTokens.gold && fg != KenteTokens.glowGold, "\(n)")
        }
    }
    @Test func statusNeverKenteGreen() {
        for c in StatusTokens.all { #expect(![KenteTokens.green, KenteTokens.greenDeep, KenteTokens.glowNeonGreen].contains(c)) }
    }
    @Test func kenteTextPairsPassAA() {
        for (n, a, b) in KenteTokens.textPairs { #expect(M3taTokens.contrast(a, b) >= 4.5, "\(n)") }
    }
    @Test func statusColorsReadable() {
        for d in [true, false] {
            let bg = d ? TMWTokens.dark.bg : TMWTokens.light.bg
            for c in [StatusTokens.good(dark: d), StatusTokens.warn(dark: d), StatusTokens.bad(dark: d)] { #expect(M3taTokens.contrast(c, bg) >= 4.5) }
        }
    }
    @Test func accentBudgetUnder15Percent() { #expect(KenteTokens.accentShare() <= 0.15) }
    @Test func tokensMatchPack() {
        #expect(KenteTokens.all == [0xF2C230, 0x7A5600, 0x3FBF3A, 0x17702A, 0xF23A2E, 0x3E6E8E, 0x5CFF4A, 0xFFD447])
    }
}

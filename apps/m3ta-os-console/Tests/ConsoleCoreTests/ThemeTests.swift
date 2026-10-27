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

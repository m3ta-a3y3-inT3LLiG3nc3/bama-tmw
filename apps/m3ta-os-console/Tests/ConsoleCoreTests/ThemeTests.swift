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

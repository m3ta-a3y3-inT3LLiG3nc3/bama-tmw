import Foundation

// Field Book Phase 1 (spec v2 §4 Phase 1, D4/D15/D16).
// Configuration for the vault-reading walking skeleton. The vault root and
// scope list are data, not code: re-pointing the app at another tree is a
// config change (config.json in the app data directory, or the
// FIELDBOOK_VAULT_ROOT environment override applied by the app layer),
// never a reinstall.

public struct FieldBookConfig: Codable, Equatable, Sendable {
    /// D1(a) tree, exact path as verified by the Phase 0 Workstream B census.
    public static let defaultVaultRootPath = "/Users/th3m3taway/Library/Mobile Documents/iCloud~md~obsidian/Documents/Otto Workspace/M3TA-Vault 2"
    /// The spec/original-scaffold bundle id (Phase 1 fix F2). The structural
    /// index and App State live under this id's Application Support folder.
    public static let bundleID = "com.th3m3taway.m3taosconsole"

    public var vaultRootPath: String
    /// Vault-shaped subtrees the reader/index is scoped to (Phase 1 task
    /// scope). Everything else in the D1(a) tree — MLXModels, workspace,
    /// Documents mirrors, code trees — is excluded by construction.
    public var scopedSubtrees: [String]
    /// Week planning file, relative to the vault root (§1.3c convention).
    public var planningWeekRelativePath: String
    /// EventKit calendar titles the Lookout may read (§1.3a allowlist).
    /// Default is the business calendar as it actually exists on the Mac:
    /// the 2026-11-09 Calendar.app recon listed 40 calendars and none
    /// carries the business domain in its title — the business calendar
    /// (info@th3m3taway.com identity) is titled "Th3 M3ta Way". An empty
    /// list falls back to `businessCalendarHint` matching on title/source.
    public var calendarAllowlist: [String]
    public var businessCalendarHint: String
    /// Files larger than this are listed as oversized in Needs attention
    /// and never parsed (§2.2 tolerance table).
    public var maxFileBytes: Int

    public init(vaultRootPath: String = FieldBookConfig.defaultVaultRootPath,
                scopedSubtrees: [String] = ["00-Inbox", "10-Projects!", "Meetings", "Global-Wiki", "knowledge"],
                planningWeekRelativePath: String = "planning/week.md",
                calendarAllowlist: [String] = ["Th3 M3ta Way"],
                businessCalendarHint: String = "th3m3taway.com",
                maxFileBytes: Int = 5_000_000) {
        self.vaultRootPath = vaultRootPath
        self.scopedSubtrees = scopedSubtrees
        self.planningWeekRelativePath = planningWeekRelativePath
        self.calendarAllowlist = calendarAllowlist
        self.businessCalendarHint = businessCalendarHint
        self.maxFileBytes = maxFileBytes
    }

    public var vaultRoot: URL { URL(fileURLWithPath: (vaultRootPath as NSString).expandingTildeInPath) }
    public var planningWeekURL: URL { vaultRoot.appendingPathComponent(planningWeekRelativePath) }

    /// Calendar allowlist decision (§1.3a): explicit list wins; otherwise a
    /// calendar is allowed only when the business hint matches its title or
    /// its source title. Personal/family calendars never render by default.
    public func calendarAllowed(title: String, sourceTitle: String) -> Bool {
        if !calendarAllowlist.isEmpty {
            let t = title.trimmingCharacters(in: .whitespaces).lowercased()
            return calendarAllowlist.contains { $0.trimmingCharacters(in: .whitespaces).lowercased() == t }
        }
        let hint = businessCalendarHint.lowercased()
        return title.lowercased().contains(hint) || sourceTitle.lowercased().contains(hint)
    }

    // MARK: App data locations (D4)

    /// ~/Library/Application Support/<bundleID>/ — demo mode gets its own
    /// subtree so its index and App State can never alias the live ones.
    public static func appDataDirectory(demo: Bool, base: URL? = nil) -> URL {
        let root = base ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = root.appendingPathComponent(bundleID)
        return demo ? dir.appendingPathComponent("demo") : dir
    }
    /// D4(a): the rebuildable structural index.
    public static func indexDirectory(demo: Bool, base: URL? = nil) -> URL {
        appDataDirectory(demo: demo, base: base).appendingPathComponent("index")
    }
    /// D4(b): non-rebuildable App State (recents, save log, sync cursors).
    /// A separate store from the index, honestly labeled: deleting it loses
    /// recents/save-log history; deleting the index loses nothing.
    public static func appStateDirectory(demo: Bool, base: URL? = nil) -> URL {
        appDataDirectory(demo: demo, base: base).appendingPathComponent("app-state")
    }

    /// Load config.json from the app data directory when present; defaults
    /// otherwise. A malformed config is an error, never a silent fallback.
    public static func load(demo: Bool, base: URL? = nil) throws -> FieldBookConfig {
        let file = appDataDirectory(demo: demo, base: base).appendingPathComponent("config.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return FieldBookConfig() }
        let data = try Data(contentsOf: file)
        return try JSONDecoder().decode(FieldBookConfig.self, from: data)
    }
}

/// Phase 1 fix F4: full-screen Space is the default launch posture.
/// Scripted probes may opt out with CONSOLE_NO_FULLSCREEN=1; that opt-out
/// is a test harness fact, never the shipped default.
public enum LaunchPosture {
    public static func shouldLaunchFullScreen(environment: [String: String]) -> Bool {
        environment["CONSOLE_NO_FULLSCREEN"] != "1"
    }
}
